/*
MIT License

Copyright (c) 2020-2022 Lars Pontoppidan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
import vab.android
import os
import vab.vxt
import vab.util as job_util
import vab.android.ndk
import crypto.md5

pub fn vab_extension_compile_no_v(source_file string, opt android.CompileOptions) ! {
	err_sig := @MOD + '.' + @FN
	os.mkdir_all(opt.work_dir) or {
		return error('${err_sig}: failed making directory "${opt.work_dir}". ${err}')
	}
	build_dir := opt.build_directory()!

	v_meta_dump := android.VMetaInfo{
		imports: []
		c_flags: []
	}
	v_cflags := v_meta_dump.c_flags
	imported_modules := v_meta_dump.imports

	v_output_file := source_file
	v_thirdparty_dir := os.join_path(vxt.home(), 'thirdparty')

	uses_gc := false

	// Poor man's cache check
	mut hash := ''
	hash_file := os.join_path(opt.work_dir, 'v_android.hash')
	if opt.cache && os.exists(build_dir) && os.exists(v_output_file) {
		mut bytes := os.read_bytes(v_output_file) or {
			return error('${err_sig}: failed reading "${v_output_file}".\n${err}')
		}
		bytes << '${opt.str()}-${opt.cache_key}'.bytes()
		hash = md5.sum(bytes).hex()

		if os.exists(hash_file) {
			prev_hash := os.read_file(hash_file) or { '' }
			if hash == prev_hash {
				if opt.verbosity > 1 {
					println('Skipping compile. Hashes match ${hash}')
				}
				return
			}
		}
	}

	if hash != '' && os.exists(v_output_file) {
		if opt.verbosity > 2 {
			println('Writing new hash ${hash}')
		}
		os.rm(hash_file) or {}
		mut hash_fh := os.open_file(hash_file, 'w+', 0o700) or {
			return error('${err_sig}: failed opening "${hash_file}". ${err}')
		}
		hash_fh.write(hash.bytes()) or {
			return error('${err_sig}: failed writing to "${hash_file}".\n${err}')
		}
		hash_fh.close()
	}

	// Remove any previous builds
	if os.is_dir(build_dir) {
		os.rmdir_all(build_dir) or {
			return error('${err_sig}: failed removing "${build_dir}": ${err}')
		}
	}
	os.mkdir(build_dir) or {
		return error('${err_sig}: failed making directory "${build_dir}".\n${err}')
	}

	archs := opt.archs()!

	if opt.verbosity > 0 {
		println('Compiling V import C dependencies (.c to .o for ${archs})' +
			if opt.parallel { ' in parallel' } else { '' })
	}

	vicd := android.compile_v_imports_c_dependencies(opt, imported_modules) or {
		return IError(android.CompileError{
			kind: .c_to_o
			err: err.msg()
		})
	}
	mut o_files := vicd.o_files.clone()
	mut a_files := vicd.a_files.clone()

	// For all compilers
	mut cflags := opt.c_flags.clone()
	mut includes := []string{}
	mut defines := []string{}
	mut ldflags := []string{}

	// Grab any external C flags
	for line in v_cflags {
		if line.contains('.tmp.c') || line.ends_with('.o"') {
			continue
		}
		if line.starts_with('-D') {
			defines << line
		}
		if line.starts_with('-I') {
			if line.contains('/usr/') {
				continue
			}
			includes << line
		}
		if line.starts_with('-l') {
			if line.contains('-lgc') {
				// compiled in
				continue
			}
			if line.contains('-lpthread') {
				// pthread is built into bionic
				continue
			}
			ldflags << line
		}
	}

	// ... still a bit of a mess
	if opt.is_prod {
		cflags << ['-Os']
	} else {
		cflags << ['-O0']
	}
	cflags << ['-fPIC', '-fvisibility=hidden', '-ffunction-sections', '-fdata-sections',
		'-ferror-limit=1']

	cflags << ['-Wall', '-Wextra']

	cflags << ['-Wno-unused-parameter'] // sokol_app.h

	// TODO V compile warnings - here to make the compiler(s) shut up :/
	cflags << ['-Wno-unused-variable', '-Wno-unused-result', '-Wno-unused-function',
		'-Wno-unused-label']
	cflags << ['-Wno-missing-braces', '-Werror=implicit-function-declaration']
	cflags << ['-Wno-enum-conversion', '-Wno-unused-value', '-Wno-pointer-sign',
		'-Wno-incompatible-pointer-types']

	defines << '-DAPPNAME="${opt.lib_name}"'
	defines << ['-DANDROID', '-D__ANDROID__', '-DANDROIDVERSION=${opt.api_level}']

	// Include NDK headers
	mut android_includes := []string{}
	ndk_sysroot := ndk.sysroot_path(opt.ndk_version) or {
		return error('${err_sig}: getting NDK sysroot path.\n${err}')
	}
	android_includes << '-I"' + os.join_path(ndk_sysroot, 'usr', 'include') + '"'
	android_includes << '-I"' + os.join_path(ndk_sysroot, 'usr', 'include', 'android') + '"'

	is_debug_build := opt.is_debug_build()

	// Sokol sapp
	if true {
		if opt.verbosity > 1 {
			println('Including sokol_sapp support via sokol.sapp module')
		}
		if is_debug_build {
			if opt.verbosity > 1 {
				println('Define SOKOL_DEBUG')
			}
			defines << '-DSOKOL_DEBUG'
		}

		if opt.verbosity > 1 {
			println('Using GLES ${opt.gles_version}')
		}

		ldflags << '-lEGL'
		if opt.gles_version == 3 {
			defines << ['-DSOKOL_GLES3']
			ldflags << '-lGLESv3'
		} else {
			defines << ['-DSOKOL_GLES2']
			ldflags << '-lGLESv2'
		}

		ldflags << ['-uANativeActivity_onCreate', '-usokol_main']
	}

	if uses_gc {
		includes << '-I"' + os.join_path(v_thirdparty_dir, 'libgc', 'include') + '"'
	}

	// misc
	ldflags << ['-llog', '-landroid', '-lm']
	ldflags << ['-shared'] // <- Android loads native code via a library in NativeActivity
	mut cflags_arm64 := ['-m64']
	mut cflags_arm32 := ['-mfloat-abi=softfp', '-m32']
	mut cflags_x86 := ['-march=i686', '-mssse3', '-mfpmath=sse', '-m32']
	mut cflags_x86_64 := ['-march=x86-64', '-msse4.2', '-mpopcnt', '-m64']

	mut arch_cc := map[string]string{}
	mut arch_libs := map[string]string{}
	for arch in archs {
		compiler := ndk.compiler(.c, opt.ndk_version, arch, opt.api_level) or {
			return error('${err_sig}: failed getting NDK compiler.\n${err}')
		}
		arch_cc[arch] = compiler

		arch_lib := ndk.libs_path(opt.ndk_version, arch, opt.api_level) or {
			return error('${err_sig}: failed getting NDK libs path.\n${err}')
		}
		arch_libs[arch] = arch_lib
	}

	mut arch_cflags := map[string][]string{}
	arch_cflags['arm64-v8a'] = cflags_arm64
	arch_cflags['armeabi-v7a'] = cflags_arm32
	arch_cflags['x86'] = cflags_x86
	arch_cflags['x86_64'] = cflags_x86_64

	if opt.verbosity > 0 {
		println('Compiling C output for ${archs}' + if opt.parallel { ' in parallel' } else { '' })
	}

	mut jobs := []job_util.ShellJob{}

	for arch in archs {
		arch_cflags[arch] << [
			'-target ' + ndk.compiler_triplet(arch) + opt.min_sdk_version.str(),
		]
		if arch == 'armeabi-v7a' {
			arch_cflags[arch] << ['-march=armv7-a']
		}
	}

	// Cross compile v.c to v.o lib files
	for arch in archs {
		arch_o_dir := os.join_path(build_dir, 'o', arch)
		if !os.is_dir(arch_o_dir) {
			os.mkdir_all(arch_o_dir) or {
				return error('${err_sig}: failed making directory "${arch_o_dir}". ${err}')
			}
		}

		arch_o_file := os.join_path(arch_o_dir, '${opt.lib_name}.o')

		// Compile .o
		build_cmd := [
			arch_cc[arch],
			cflags.join(' '),
			android_includes.join(' '),
			includes.join(' '),
			defines.join(' '),
			arch_cflags[arch].join(' '),
			'-c "${v_output_file}"',
			'-o "${arch_o_file}"',
		]

		o_files[arch] << arch_o_file

		jobs << job_util.ShellJob{
			cmd: build_cmd
		}
	}

	job_util.run_jobs(jobs, opt.parallel, opt.verbosity) or {
		return IError(android.CompileError{
			kind: .c_to_o
			err: err.msg()
		})
	}
	jobs.clear()

	if opt.no_so_build && opt.verbosity > 1 {
		println('Skipping .so build since .no_so_build == true')
	}

	// Cross compile .o files to .so lib file
	if !opt.no_so_build {
		for arch in archs {
			arch_lib_dir := os.join_path(build_dir, 'lib', arch)
			os.mkdir_all(arch_lib_dir) or {
				return error('${err_sig}: failed making directory "${arch_lib_dir}".\n${err}')
			}

			arch_o_files := o_files[arch].map('"${it}"')
			arch_a_files := a_files[arch].map('"${it}"')

			build_cmd := [
				arch_cc[arch],
				arch_o_files.join(' '),
				'-o "${arch_lib_dir}/lib${opt.lib_name}.so"',
				arch_a_files.join(' '),
				'-L"' + arch_libs[arch] + '"',
				ldflags.join(' '),
			]

			jobs << job_util.ShellJob{
				cmd: build_cmd
			}
		}

		job_util.run_jobs(jobs, opt.parallel, opt.verbosity) or {
			return IError(android.CompileError{
				kind: .o_to_so
				err: err.msg()
			})
		}

		if 'armeabi-v7a' in archs {
			// TODO fix DT_NAME crash instead of including a copy of the armeabi-v7a lib
			armeabi_lib_dir := os.join_path(build_dir, 'lib', 'armeabi')
			os.mkdir_all(armeabi_lib_dir) or {
				return error('${err_sig}: failed making directory "${armeabi_lib_dir}".\n${err}')
			}

			armeabi_lib_src := os.join_path(build_dir, 'lib', 'armeabi-v7a', 'lib${opt.lib_name}.so')
			armeabi_lib_dst := os.join_path(armeabi_lib_dir, 'lib${opt.lib_name}.so')
			os.cp(armeabi_lib_src, armeabi_lib_dst) or {
				return error('${err_sig}: failed copying "${armeabi_lib_src}" to "${armeabi_lib_dst}".\n${err}')
			}
		}
	}
}
