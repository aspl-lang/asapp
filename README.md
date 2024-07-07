<div align="center">
<img src="logo.png" alt="ASAPP logo" width="200"/>

# ASAPP
...is an Android application builder for ASPL.
</div>

Using ASAPP, you can easily compile and deploy nearly any ASPL application to the Android platform in a matter of minutes.

## Usage
### Building ASAPP
ASAPP is written in the V programming language, which makes it super easy to build:

1. Install [`vab`](https://github.com/vlang/vab)
```bash
v install vab
```

2. Clone the ASAPP repository
```bash
git clone https://github.com/ASPLGithub/ASAPP
```

3. Build the ASAPP source files
```bash
v -o asapp .
```

4. Optionally, you can also add the ASAPP binary to your PATH to make it accessible from anywhere
```bash
sudo ln -s /path/to/asapp /usr/local/bin/asapp
```
(for Windows instructions for this step, just google how to add an executable to the PATH)

### Using ASAPP
Building an ASPL application for Android requires two steps:

1. Compile the ASPL application to an intermediate language (e.g. C or AIL; note that **only C is currently supported**)
```bash
aspl -keeptemp compile path/to/your/app
```

2. Build the application for Android
```bash
asapp --app-name "Your App Name" --package-id "com.your.app.id"
```

ASAPP will automatically pick the intermediate language file that has the same name as "Your App Name" and package it into an Android APK.

There are many other options available for ASAPP, which you can view by running `asapp help`.

Note: There is currently no CLI option for permissions; if you want your app to have a certain permission, simply add `<uses-permission android:name="android.permission.YOUR_PERMISSION" />` to the `AndroidManifest.xml` that is part of your `vab` installation.

## License & Credits
ASAPP is licensed under the MIT License. See the [LICENSE](LICENSE) file for more information.

### Logo
> "The Android robot is reproduced or modified from work created and shared by Google and used according to terms described in the Creative Commons 3.0 Attribution License."