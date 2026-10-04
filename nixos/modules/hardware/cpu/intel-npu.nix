{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.cpu.intel.npu;
in
{
  options = {
    hardware.cpu.intel.npu = {
      enable = lib.mkEnableOption "Intel NPU support";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.intel-npu-driver.validation
      pkgs.level-zero
    ];

    hardware = {
      firmware = [ pkgs.intel-npu-driver.firmware ];
      graphics = {
        enable = true;
        # The OpenVINO NPU plugin dlopens its compiler loader
        # (libopenvino_intel_npu_compiler_loader.so) from the directory of
        # libze_intel_npu.so, so the compiler must be assembled into
        # /run/opengl-driver/lib next to the driver. Without it, the plugin
        # fails to compile models and silently falls back to CPU.
        extraPackages = [
          pkgs.intel-npu-driver
          pkgs.intel-npu-compiler
        ];
      };
    };
  };
}
