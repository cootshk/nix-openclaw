{
  lib,
  stdenvNoCC,
  fetchzip,
}:

stdenvNoCC.mkDerivation {
  pname = "openclaw-app";
  version = "2026.5.27";

  src = fetchzip {
    url = "https://github.com/openclaw/openclaw/releases/download/v2026.5.27/OpenClaw-2026.5.27.zip";
    hash = "sha256-ogxmSCcMUCsK2Y2xsHcLx2hi6IJRH8xgTybowQDWG58=";
    stripRoot = false;
  };

  dontUnpack = true;

  installPhase = "${../scripts/openclaw-app-install.sh}";

  meta = with lib; {
    description = "OpenClaw macOS app bundle";
    homepage = "https://github.com/openclaw/openclaw";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
