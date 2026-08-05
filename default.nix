

# #+name: time-tracker-nix
# #+header: :noweb yes :noweb-prefix no
# #+header: :tangle (concat (org-entry-get nil "repo-path" t) "/default.nix")
# #+header: :comments both

# [[file:../../../org/repositories.org::time-tracker-nix][time-tracker-nix]]
let
  pkgs = import <nixpkgs> {
    config = {
      allowUnfree = true;
      android_sdk.accept_license = true;
    };
  };

  # The Android NDK toolchain ships only as x86_64 ELFs. They run on this
  # aarch64 host under qemu-user (boot.binfmt.emulatedSystems set in
  # configuration.nix), but the dynamic linker needs to find x86_64 versions
  # of libc, libz, libncurses, libstdc++, etc. We materialise them in a
  # single sysroot and point QEMU_LD_PREFIX / LD_LIBRARY_PATH at it.
  x86Pkgs = import <nixpkgs> {
    system = "x86_64-linux";
    config = {
      allowUnfree = true;
      android_sdk.accept_license = true;
    };
  };

  x86Sysroot = pkgs.buildEnv {
    name = "x86_64-emu-sysroot";
    paths = with x86Pkgs; [
      glibc
      zlib
      ncurses
      stdenv.cc.cc.lib
    ];
  };

  androidComposition = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "36" "35" "34" "33" ];
    buildToolsVersions = [ "36.0.0" "35.0.0" "28.0.3" ];
    includeEmulator = false;
    includeSystemImages = false;
    includeNDK = true;
    ndkVersions = [ "28.2.13676358" ];
    includeCmake = true;
    cmakeVersions = [ "3.22.1" ];
  };

  # androidenv ships x86_64 platform-tools. On aarch64 the bundled adb/fastboot
  # ELF binaries are 0x3E (x86_64) and refuse to exec. Rebuild the SDK tree with
  # platform-tools replaced by pkgs.android-tools (native aarch64).
  patchedAndroidSdk = pkgs.runCommand "android-sdk-aarch64" {} ''
    mkdir -p $out/libexec/android-sdk/platform-tools
    cd ${androidComposition.androidsdk}/libexec/android-sdk
    for d in *; do
      if [ "$d" != "platform-tools" ]; then
        ln -s "${androidComposition.androidsdk}/libexec/android-sdk/$d" "$out/libexec/android-sdk/$d"
      fi
    done
    ln -s ${pkgs.android-tools}/bin/adb      $out/libexec/android-sdk/platform-tools/adb
    ln -s ${pkgs.android-tools}/bin/fastboot $out/libexec/android-sdk/platform-tools/fastboot
    for f in platform-tools/*; do
      name=$(basename $f)
      case "$name" in
        adb|fastboot) ;;
        *) ln -s "${androidComposition.androidsdk}/libexec/android-sdk/$f" "$out/libexec/android-sdk/platform-tools/$name" ;;
      esac
    done
  '';

  lib = import /home/martin/.nix-defexpr/lib.nix { inherit pkgs; };
in lib.mkVenv {
  name = "time_tracker";
  env = {
    ANDROID_HOME      = "${patchedAndroidSdk}/libexec/android-sdk";
    ANDROID_SDK_ROOT  = "${patchedAndroidSdk}/libexec/android-sdk";
    JAVA_HOME         = "${lib.jdk}";
    FLUTTER_ROOT      = "${pkgs.flutter}";
    CHROME_EXECUTABLE = "${pkgs.chromium}/bin/chromium";
    QEMU_LD_PREFIX    = "${x86Sysroot}";
    LD_LIBRARY_PATH   = "${x86Sysroot}/lib";
    # `just web-smoke` drives the built PWA with playwright-core (from
    # package.json); the browser binaries come from nixpkgs instead of
    # `npx playwright install`. Keep package.json's playwright version in
    # step with this one.
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
  };
  paths = [
    pkgs.flutter
    lib.jdk
    pkgs.pkg-config
    pkgs.android-tools
    pkgs.scrcpy
    pkgs.chromium
    pkgs.chromedriver
    pkgs.just
    # Web PWA smoke test: node runs tool/web_smoke.mjs, and chromium has to be
    # headed under Xvfb — headless swiftshader paints blank CanvasKit frames.
    pkgs.nodejs
    pkgs.xvfb-run
    patchedAndroidSdk
  ];
}
# time-tracker-nix ends here
