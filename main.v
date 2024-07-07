import os
import flag
import vab.android
import vab.android.sdk
import vab.cli

// TODO: Add a CLI option for specifying permissions

@[params]
struct ASAPPOptions {
	app_name     string
	package_id   string
	output_file  string
	icon         string
	version_code int
	prod         bool
	verbosity    int
}

const default_api_level = '29'
const default_ndk_version = '21.1.6352462'

fn locate_aspl_installation() string {
	return os.abs_path('ASPL') // TODO: Properly locate the ASPL installation
}

fn build(options ASAPPOptions) ! {
	lib_name := options.app_name.replace(' ', '_').to_lower()
	work_dir := cli.work_directory

	mut c_flags := [
		'-I ' + locate_aspl_installation() or { panic('No ASPL installation found in PATH') },
		'-I ' + locate_aspl_installation() or { panic('No ASPL installation found in PATH') } +
			'/thirdparty/libgc/include',
		'-Wno-sign-compare',
		'-DASPL_APP_NAME_STRING=\\"' + options.app_name + '\\"',
		'-DSTBIR_NO_SIMD', // TODO: Find a way to enable SIMD
		'-DICYLIB_NO_SIMD',
		'-D_REENTRANT',
		//'-DUSE_MMAP', // TODO: Is this required? See vab
		// -lpthread is not required, as it is already included in Bionic
	]
	if !options.prod {
		c_flags << '-DASPL_DEBUG'
		c_flags << '-DGC_ASSERTIONS'
		c_flags << '-DGC_ANDROID_LOG'
	}
	c_flags << '-DGC_DEBUG' // TODO: The app crashes randomly without this flag

	mut v_flags := [
		'-gc none', // The GC is already #included in the C source file, so we don't need it to build it again
	]
	if !options.prod {
		v_flags << '-cg'
	}

	compile_opt := android.CompileOptions{
		lib_name: lib_name
		api_level: default_api_level
		ndk_version: default_ndk_version
		archs: android.default_archs.clone()
		work_dir: work_dir
		c_flags: c_flags
		v_flags: v_flags
		is_prod: options.prod
		verbosity: options.verbosity
	}
	vab_extension_compile_no_v(os.abs_path(options.app_name + '.c'), compile_opt)!

	package_opt := android.PackageOptions{
		app_name: options.app_name
		lib_name: lib_name
		package_id: options.package_id
		activity_name: 'VActivity'
		output_file: os.abs_path(options.output_file)
		api_level: default_api_level
		work_dir: work_dir
		icon: os.abs_path(options.icon)
		build_tools: sdk.default_build_tools_version
		keystore: android.default_keystore(vab_extension_cache_dir())! // TODO: Allow the user to specify a keystore
		verbosity: options.verbosity
		version_code: options.version_code
	}
	android.package(package_opt)!
}

fn main() {
	mut fp := flag.new_flag_parser(os.args)
	fp.application('ASAPP')
	fp.version('v0.1')
	fp.limit_free_args(0, 0)!
	fp.description('Deploy ASPL apps to Android')
	fp.skip_executable()
	app_name := fp.string_opt('app-name', 0, 'the name of this application') or {
		eprintln('ASAPP: app-name is required')
		return
	}
	package_id := fp.string_opt('package-id', 0, 'the package ID of this application') or {
		eprintln('ASAPP: package-id is required')
		return
	}
	output_file := fp.string('output_file', 0, app_name + '.apk', 'the output file of this application')
	icon := fp.string('icon', 0, 'logo.png', 'the icon of this application')
	version_code := fp.int('version-code', 0, 0, 'the version code of this application')
	prod := fp.bool('prod', 0, false, 'whether to build this application in production mode')
	verbosity := fp.int('verbosity', `v`, 4, 'the verbosity level of this application')

	fp.finalize() or {
		eprintln(err)
		println(fp.usage())
		return
	}

	if locate_aspl_installation() == none {
		eprintln('ASAPP: no ASPL installation found in PATH')
		return
	}

	build(
		app_name: app_name
		package_id: package_id
		output_file: output_file
		icon: icon
		version_code: version_code
		prod: prod
		verbosity: verbosity
	)!
}
