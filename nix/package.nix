{
  lib,
  stdenv,
  dockerTools,
  patchelf,
  zlib,
  # libcrypt.so.1. Pass pkgs.libxcrypt-legacy. Current libxcrypt is .so.2 only.
  libcrypt,
  jq,
  gnutar,
  gzip,
  python3,
}:

let
  release = import ./release.nix;

  # The engine is not published as source. Upstream ships it as this image:
  # a static Go waf-service plus an OpenResty/nginx built with prefix /uuwaf.
  image = dockerTools.pullImage {
    imageName = release.imageName;
    imageDigest = release.imageDigest;
    finalImageName = "uusec-waf";
    finalImageTag = release.version;
    hash = release.imageHash;
  };

  libPath = lib.makeLibraryPath [
    zlib
    libcrypt
    stdenv.cc.cc.lib
  ];
in
stdenv.mkDerivation {
  pname = "uusec-waf";
  version = release.version;

  src = image;

  nativeBuildInputs = [
    patchelf
    jq
    gnutar
    gzip
    python3
  ];

  unpackPhase = ''
    runHook preUnpack
    mkdir -p unpacked rootfs
    tar -xf "$src" -C unpacked
    mapfile -t layers < <(jq -r '.[0].Layers[]' unpacked/manifest.json)
    for layer in "''${layers[@]}"; do
      python3 ${./extract-uuwaf.py} "unpacked/$layer" rootfs
    done
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;
  # fixup would drop the libcrypt and libstdc++ rpaths, and strip can
  # break the static Go binaries.
  dontPatchELF = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    if [ ! -x rootfs/uuwaf/waf-service ]; then
      echo "uusec/waf image is missing /uuwaf/waf-service" >&2
      exit 1
    fi

    mkdir -p "$out/uuwaf" "$out/bin"
    cp -a rootfs/uuwaf/. "$out/uuwaf/"
    chmod -R u+rwX,go+rX "$out/uuwaf"

    substituteInPlace "$out/uuwaf/conf/uuwaf.conf" \
      --replace-fail "/etc/ssl/certs/ca-bundle.crt" "/etc/ssl/certs/ca-certificates.crt" \
      --replace-fail "/tmp/disk_cache_uuwaf" "/var/cache/uusec-waf"

    printf '%s\n' "${release.version}" > "$out/uuwaf/.version"

    # nginx and the Lua modules are linked against glibc, libz, libcrypt,
    # libstdc++, and the bundled LuaJIT. The Go programs are static.
    rpath="${libPath}:$out/uuwaf/luajit/lib:/uuwaf/luajit/lib"
    while IFS= read -r -d "" elf; do
      if readelf -l "$elf" 2>/dev/null | grep -q "Requesting program interpreter"; then
        patchelf --set-interpreter "${stdenv.cc.bintools.dynamicLinker}" \
          --force-rpath --set-rpath "$rpath" "$elf"
      elif readelf -d "$elf" 2>/dev/null | grep -q "(NEEDED)"; then
        patchelf --force-rpath --set-rpath "$rpath" "$elf"
      fi
    done < <(find "$out/uuwaf" -type f -print0)

    substitute ${./uusec-waf-prepare.sh} "$out/bin/uusec-waf-prepare" \
      --replace-fail '@pkg@' "$out/uuwaf"
    chmod 755 "$out/bin/uusec-waf-prepare"
    install -m 755 ${./uusec-waf-run.sh} "$out/bin/uusec-waf"

    if ldd "$out/uuwaf/sbin/uuwaf" | grep -q 'not found'; then
      echo "uuwaf is missing libraries after patchelf:" >&2
      ldd "$out/uuwaf/sbin/uuwaf" >&2
      exit 1
    fi

    runHook postInstall
  '';

  meta = {
    description = "UUSEC WAF packaged to run on NixOS without Docker";
    homepage = "https://github.com/Safe3/uusec-waf";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "uusec-waf";
  };
}
