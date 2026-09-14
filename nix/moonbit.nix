# The MoonBit toolchain, as a Nix package.
#
# Upstream ships a single tarball of prebuilt binaries plus a separately
# distributed standard library. Neither is in nixpkgs at a version new enough to
# have `moon prove`, which this project depends on, so the toolchain is packaged
# here from the official artifacts pinned in `nix/toolchain.lock.json`.
#
# Two things make this less trivial than "unpack a tarball":
#
#   * The standard library ships as *source* and has to be bundled — the
#     compiler wants `lib/core/_build/<target>/release/bundle`, which is
#     produced by `moon bundle --all`. That runs at build time, here, so the
#     result is cached in the store rather than rebuilt in every developer's
#     home directory.
#
#   * `moon` locates everything relative to `MOON_HOME` by default, and
#     `MOON_HOME` also holds the mutable package registry and caches. Pointing
#     it at a read-only store path would break `moon add`. `MOON_TOOLCHAIN_ROOT`
#     is the read-only half of that split, so the wrappers set that and leave
#     `MOON_HOME` alone.
{
  lib,
  stdenv,
  fetchurl,
  unzip,
  makeWrapper,
  autoPatchelfHook ? null,
  lock,
}:
let
  system = stdenv.hostPlatform.system;
  spec =
    lock.moonbit.platforms.${system}
      or (throw "the MoonBit toolchain is not pinned for ${system}; add it to tools/nix/toolchain.lock.json");

  toolchain = fetchurl {
    url = "${lock.moonbit.baseUrl}/${spec.asset}";
    hash = spec.hash;
  };

  core = fetchurl {
    url = lock.moonbit.coreUrl;
    hash = lock.moonbit.coreHash;
  };

  # Every executable the toolchain ships. Wrapped rather than symlinked so that
  # `MOON_TOOLCHAIN_ROOT` is set no matter how the binary is invoked.
  executables = [
    "moon"
    "moonc"
    "moonrun"
    "moonfmt"
    "mooninfo"
    "moondoc"
    "mooncake"
    "moon-lsp"
    "moon-ide"
    "moon-cram"
    "moon-wasm-opt"
    "moon_cove_report"
  ];
in
stdenv.mkDerivation {
  pname = "moonbit";
  version = lock.moonbit.version;

  srcs = [ toolchain core ];

  nativeBuildInputs = [ unzip makeWrapper ]
    ++ lib.optional (stdenv.hostPlatform.isLinux && autoPatchelfHook != null) autoPatchelfHook;

  # `moon-cram` and `mooncake` are linked against libgcc's runtime, which the
  # store does not put on any default search path. Named here so that
  # `autoPatchelf` has somewhere to find it; without it the patch step fails
  # with `could not satisfy dependency libgcc_s.so.1`, which is accurate and
  # says nothing about where to get one.
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  # The archives have no shared top-level directory, so unpacking is explicit.
  unpackPhase = ''
    runHook preUnpack
    mkdir -p toolchain
    tar -xzf ${toolchain} -C toolchain
    unzip -q ${core} -d toolchain/lib
    runHook postUnpack
  '';

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    chmod -R u+w toolchain
    chmod +x toolchain/bin/* || true

    # Patch the interpreter and library paths *now*, not in `fixupPhase`.
    #
    # These are prebuilt binaries linked against an FHS the store does not have,
    # and `autoPatchelfHook` normally repairs them after the build. This
    # derivation runs one of them during the build — `moon bundle`, below — so
    # by then is too late: the binary is still asking for `/lib64/ld-linux` and
    # the kernel answers `cannot execute: required file not found`, which names
    # neither the file nor the reason.
    #
    # It was hidden for as long as CI had the built derivation in its `/nix/store`
    # cache, and surfaced the first time the toolchain pin moved and the cache
    # key with it.
    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      autoPatchelf toolchain/bin toolchain/lib
    ''}

    # Bundle the standard library for every backend the project targets. `moon`
    # writes into the core tree itself, which is why this happens before the
    # tree is copied into the (read-only) store output.
    export MOON_TOOLCHAIN_ROOT="$PWD/toolchain"
    export PATH="$PWD/toolchain/bin:$PATH"
    export HOME="$TMPDIR"
    for target in wasm wasm-gc js; do
      moon -C toolchain/lib/core bundle --all --target "$target"
    done
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r toolchain/lib toolchain/include toolchain/share "$out/" 2>/dev/null || true
    mkdir -p "$out/libexec" "$out/bin"
    cp -r toolchain/bin/* "$out/libexec/"
    for exe in ${lib.escapeShellArgs executables}; do
      if [ -f "$out/libexec/$exe" ]; then
        makeWrapper "$out/libexec/$exe" "$out/bin/$exe" \
          --set-default MOON_TOOLCHAIN_ROOT "$out"
      fi
    done
    runHook postInstall
  '';

  # The binaries are upstream's own builds; stripping or rewriting them has no
  # benefit and risks breaking the embedded runtime objects they link against.
  dontStrip = true;
  dontPatchELF = stdenv.hostPlatform.isDarwin;

  meta = {
    description = "The MoonBit toolchain (compiler, build system, verifier driver)";
    homepage = "https://www.moonbitlang.com/";
    # Prebuilt binaries under MoonBit's own terms; redistributable, not open
    # source. The flake allow-lists exactly this package rather than turning on
    # unfree packages globally.
    license = lib.licenses.unfreeRedistributable;
    platforms = builtins.attrNames lock.moonbit.platforms;
    mainProgram = "moon";
  };
}
