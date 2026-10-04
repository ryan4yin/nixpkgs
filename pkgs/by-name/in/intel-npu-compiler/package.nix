{
  lib,
  stdenv,
  runCommand,
  fetchFromGitHub,
  cacert,
  git,
  git-lfs,
  cmake,
  ninja,
  pkg-config,
  python3,
  onetbb,
  pugixml,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "intel-npu-compiler";
  version = "2026.38rc1";
  compilerTag = "npu_ud_2026_38_rc1";

  # OpenVINO Intel NPU Compiler (VPUXCompilerL0). The compiler lives in its own
  # repository and is built as "CiD" (compiler in driver) inside an OpenVINO
  # source tree, the same way Intel's release pipeline builds it.
  #
  # Fetched with git instead of fetchFromGitHub because the repository needs
  # submodules (Intel's LLVM/MLIR fork) and git-lfs objects (prebuilt software
  # runtime kernels that get embedded into the compiler), and GitHub no longer
  # serves submodule archives for it.
  npuCompilerSrc =
    runCommand "npu-compiler-src-${finalAttrs.compilerTag}"
      {
        nativeBuildInputs = [
          git
          git-lfs
        ];
        GIT_SSL_CAINFO = "${cacert}/etc/ssl/certs/ca-bundle.crt";
        outputHashMode = "recursive";
        outputHash = "sha256-K325h4FBjOqmDauNXoCDoz2o5LqY5Ya9QygMsT0uvc4=";
      }
      ''
        git init npu_compiler
        cd npu_compiler
        git remote add origin https://github.com/openvinotoolkit/npu_compiler
        git fetch --depth 1 origin ${finalAttrs.compilerTag}
        git checkout FETCH_HEAD
        git submodule update --init --recursive
        git lfs install --local
        git lfs pull
        git submodule foreach --recursive 'git lfs install --local && git lfs pull'
        find . -name .git -prune -exec rm -rf {} +
        cp -r --no-preserve=mode $PWD $out
      '';

  # The OpenVINO revision this compiler tag was cut against (linux-npu-driver
  # v1.38.0: "built using OpenVINO_rev.d8047fb"). It cannot reuse the openvino
  # package's source: this compiler expects targets (openvino::level-zero-ext,
  # openvino::npu_zero_utils) that later OpenVINO releases no longer provide.
  # Bump together with openvino.
  openvinoSrc = fetchFromGitHub {
    owner = "openvinotoolkit";
    repo = "openvino";
    rev = "d8047fb380b27a9d5827cb3f22aec7781ae5ac82";
    fetchSubmodules = true;
    hash = "sha256-djEof2C5T5EyKz5hy4TQdW0Q1WHZYVHYFLujox90r/I=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    python3
    git
  ];

  buildInputs = [
    onetbb
    pugixml
  ];

  unpackPhase = ''
    runHook preUnpack
    mkdir npu_compiler openvino
    cp -r --no-preserve=mode ${finalAttrs.npuCompilerSrc}/. npu_compiler/
    cp -r --no-preserve=mode ${finalAttrs.openvinoSrc}/. openvino/
    runHook postUnpack
  '';

  postPatch = ''
    patch -d npu_compiler/thirdparty/llvm-project -Np1 -i ${./llvm-disable-atomic-check.patch}
    patch -d npu_compiler -Np1 -i ${./npu-compiler-disable-werror.patch}
    patch -d npu_compiler -Np1 -i ${./npu-compiler-fix-install.patch}
    patch -d npu_compiler -Np1 -i ${./vm-runtime-fix-install.patch}
    patch -d npu_compiler -Np1 -i ${./no-git-source.patch}
    patch -d npu_compiler/thirdparty/elf -Np1 -i ${./elf-fix-install.patch}
    patch -d openvino -Np1 -i ${./openvino-disable-werror.patch}

    # The CiD preset expects the compiler's own CMakePresets.json in the
    # OpenVINO source dir.
    cp npu_compiler/CMakePresets.json openvino/CMakePresets.json
  '';

  # Upstream recommends >= 32 GB of RAM for this build.
  configurePhase = ''
    runHook preConfigure

    export NPU_PLUGIN_HOME=$PWD/npu_compiler
    export CONFIG=Release

    cmake -B build -S openvino --preset cid-linux \
      -DCMAKE_INSTALL_PREFIX=$out \
      -DENABLE_NPU_PLUGIN_ENGINE=ON \
      -DENABLE_SYSTEM_TBB=ON \
      -DENABLE_SYSTEM_PUGIXML=ON \
      -DCMAKE_C_COMPILER_LAUNCHER= \
      -DCMAKE_CXX_COMPILER_LAUNCHER= \
      -Wno-dev

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    cmake --build build --target \
      openvino_intel_npu_compiler \
      openvino_intel_npu_compiler_loader \
      openvino_intel_npu_vm_runtime \
      -- -j"$NIX_BUILD_CORES"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cmake --install build --component CiD
    runHook postInstall
  '';

  meta = {
    description = "OpenVINO Intel NPU Compiler (VPUXCompilerL0)";
    homepage = "https://github.com/openvinotoolkit/npu_compiler";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ ryan4yin ];
    platforms = [ "x86_64-linux" ];
  };
})
