{ lib, stdenv, lua5_4, makeWrapper, p7zip, libxml2, wget, curl, rsync, unrar }:
stdenv.mkDerivation rec {
 
  pname = "hmm";
  version = "0.0.1";

  src = ./.;

  nativeBuildInputs = [
    makeWrapper
  ];

  buildInputs = [
    lua5_4
    libxml2
    wget
    curl
    rsync
    p7zip
    unrar
  ];

  isExecutable = true;

  buildPhase = ''
    sed -i '1 s/lua5.4/lua/' hmm.lua
  '';

  installPhase = ''
    mkdir -p "$out/share/lua/hmm"
    cp -r modules/ json_lua/ util.lua base.lua json.lua "$out/share/lua/hmm"

    mkdir "$out/bin"
    cp hmm.lua "$out/bin/hmm"
  '';

  postFixup = ''
    wrapProgram $out/bin/hmm \
      --set LUA_PATH ";;$out/share/lua/?.lua;$out/share/lua/?/init.lua" \
      --prefix PATH : "${p7zip}/bin:${libxml2}/bin:${wget}/bin:${rsync}/bin:${curl}/bin:${unrar}/bin"
  '';

}


