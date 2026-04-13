{ pkgs, system, version, tag, sha256 }:

let
  isDarwin = pkgs.lib.hasSuffix "darwin" system;
  nixArch = if pkgs.lib.hasPrefix "aarch64" system then "aarch64" else "x86_64";

  # URL construction
  # Release category: "swift-6.3-release" from tag "swift-6.3-RELEASE"
  category = builtins.replaceStrings ["RELEASE"] ["release"] tag;

  # macOS
  darwinUrl = "https://download.swift.org/${category}/xcode/${tag}/${tag}-osx.pkg";

  # Linux — default to ubuntu24.04 for now
  linuxPlatform = "ubuntu2404" + (if nixArch == "aarch64" then "-aarch64" else "");
  linuxFileSuffix = "ubuntu24.04" + (if nixArch == "aarch64" then "-aarch64" else "");
  linuxUrl = "https://download.swift.org/${category}/${linuxPlatform}/${tag}/${tag}-${linuxFileSuffix}.tar.gz";

  url = if isDarwin then darwinUrl else linuxUrl;

  src = pkgs.fetchurl {
    inherit url sha256;
  };

  # The inner .pkg directory name follows this pattern
  innerPkg = "${tag}-osx-package.pkg";

in
pkgs.stdenv.mkDerivation {
  pname = "swift-toolchain";
  inherit version src;

  # Don't try to unpack automatically
  dontUnpack = true;

  nativeBuildInputs = if isDarwin then [
    pkgs.xar
    pkgs.cpio
    pkgs.darwin.sigtool
  ] else [
    pkgs.autoPatchelfHook
  ];

  buildInputs = pkgs.lib.optionals (!isDarwin) [
    pkgs.stdenv.cc.cc.lib  # libstdc++
    pkgs.ncurses
    pkgs.libedit
    pkgs.libxml2
    pkgs.curl
    pkgs.libuuid
    pkgs.zlib
    pkgs.sqlite
    pkgs.python312
  ];

  installPhase = if isDarwin then ''
    runHook preInstall

    # Extract the .pkg (xar archive)
    mkdir -p pkg_contents
    cd pkg_contents
    xar -xf $src

    # Extract the Payload (gzip'd cpio)
    mkdir -p $out
    cd $out
    zcat $NIX_BUILD_TOP/pkg_contents/${innerPkg}/Payload | cpio -id 2>/dev/null

    # Move usr/* to top level so we get $out/bin/swift etc.
    if [ -d "$out/usr" ]; then
      mv $out/usr/* $out/
      rmdir $out/usr
    fi

    runHook postInstall
  '' else ''
    runHook preInstall

    mkdir -p $out tmp_extract
    tar xzf $src --strip-components=2 --no-same-owner -C tmp_extract
    cp -a tmp_extract/* $out/
    rm -rf tmp_extract

    runHook postInstall
  '';

  # On Linux, set up search paths and compat symlinks before autoPatchelfHook runs
  preFixup = pkgs.lib.optionalString (!isDarwin) ''
    # Add the toolchain's own lib directories so bundled Swift
    # runtime libraries are found by autoPatchelfHook.
    addAutoPatchelfSearchPath $out/lib
    addAutoPatchelfSearchPath $out/lib/swift/linux

    # The Ubuntu-built binaries expect Ubuntu sonames which differ from
    # nixpkgs. Create a compat directory with symlinks.
    mkdir -p $out/lib/compat
    # Point Ubuntu sonames to the actual nixpkgs shared libraries.
    # The Ubuntu binaries expect libxml2.so.2 and libedit.so.2, but nixpkgs
    # has different soname versions (libxml2.so.16, libedit.so.0).
    ln -sf "$(ls ${pkgs.libxml2.out}/lib/libxml2.so.* | head -1)" $out/lib/compat/libxml2.so.2
    ln -sf "$(ls ${pkgs.libedit.out}/lib/libedit.so.* | head -1)" $out/lib/compat/libedit.so.2
    addAutoPatchelfSearchPath $out/lib/compat
  '';

  postFixup = if isDarwin then ''
    # Make the toolchain work in pure Nix environments (sandbox):
    # swiftc's bundled clang invokes its co-located "ld" to link.
    # The toolchain ships LLD but its ld64 personality doesn't support
    # the macOS platform version on this system. Replace with nixpkgs'
    # ld64 from cctools which is a proper Apple-compatible linker.
    rm -f $out/bin/ld
    ln -s ${pkgs.darwin.binutils-unwrapped}/bin/ld $out/bin/ld

    # SwiftPM hardcodes /usr/bin/xcrun which doesn't exist in the Nix
    # sandbox. Binary-patch all SwiftPM binaries to use "xcrun" (PATH
    # lookup) instead. This is the same fix nixpkgs applies to their
    # SwiftPM source before compiling (sed 's|/usr/bin/xcrun|xcrun|g').
    # We null-pad to keep the same byte length.
    for bin in $out/bin/swift-build $out/bin/swift-package $out/bin/swift-run $out/bin/swift-test $out/bin/swift-plugin-server; do
      if [ -f "$bin" ]; then
        sed -i "s|/usr/bin/xcrun|xcrun\x00\x00\x00\x00\x00\x00\x00\x00\x00|g" "$bin"
        # Re-sign after patching — macOS kills binaries with invalid signatures
        codesign -fs - "$bin"
      fi
    done

    # Provide xcrun (from xcbuild) and libtool/vtool (from cctools) so
    # SwiftPM can find them via PATH lookup after the binary patch above.
    ln -sf ${pkgs.xcbuild}/bin/xcrun $out/bin/xcrun
    ln -sf ${pkgs.darwin.cctools}/bin/libtool $out/bin/libtool
    ln -sf ${pkgs.darwin.cctools}/bin/vtool $out/bin/vtool
  '' else "";

  meta = with pkgs.lib; {
    description = "Swift ${version} toolchain";
    homepage = "https://swift.org";
    license = licenses.asl20;
    platforms = if isDarwin then platforms.darwin else platforms.linux;
  };
}
