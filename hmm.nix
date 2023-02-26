{ lib, stdenv, lua5_4, makeWrapper
, makeDesktopItem, libxml2, p7zip, curl, wget
, rsync, unar, xdg-utils, gnome
}:

stdenv.mkDerivation rec {
 
  pname = "hmm";
  version = "0.0.1";

  src = ./.;

  nativeBuildInputs = [
    makeWrapper
  ];

  buildInputs = [
    curl
    libxml2
    lua5_4
    rsync
    unar
    wget
    xdg-utils
    gnome.zenity
  ];

  isExecutable = true;

  buildPhase = ''
    sed -i '1 s/lua5.4/lua/' hmm.lua hmm-nxm.lua
  '';

  installPhase = ''
    mkdir -p "$out/share/lua/hmm"
    cp -r modules/ json_lua/ util.lua base.lua json.lua "$out/share/lua/hmm"

    mkdir "$out/bin"
    cp hmm.lua "$out/bin/hmm"
    cp hmm-nxm.lua "$out/bin/hmm-nxm"

    mkdir -p "$out/share/applications"
    cp hmm-nxm.desktop "$out/share/applications"
  '';

  postFixup = ''
    PREFIX="${libxml2}/bin:${wget}/bin:${rsync}/bin:${curl}/bin:${unar}/bin:${xdg-utils}:${gnome.zenity}"

    wrapProgram $out/bin/hmm \
      --set LUA_PATH ";;$out/share/lua/?.lua;$out/share/lua/?/init.lua" \
      --prefix PATH : $PREFIX

    wrapProgram $out/bin/hmm-nxm \
      --set LUA_PATH ";;$out/share/lua/?.lua;$out/share/lua/?/init.lua" \
      --prefix PATH : $PREFIX
  '';

  desktopItems = [(makeDesktopItem {
    desktopName = "hmm-nxm";
    name = "hmm-nxm";
    exec = "hmm-nxm %u";
    icon = "";
    comment = "hmm nexus download handler";
    type = "Application";
    categories = [ "Network" ];
    mimeTypes = [ "x-scheme-handler/nxm" ];
  })];
}


