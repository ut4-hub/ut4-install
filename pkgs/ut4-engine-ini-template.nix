# Engine.ini template containing the OnlineSubsystemMcp redirect sections that
# point UT4 at the supplied master server domain. Per the timiimit canonical
# instructions, these sections are appended to the user's Engine.ini in
# Saved/Config/LinuxNoEditor/. The launcher seeds the file at first run.
{ pkgs, masterServerDomain }:
let
  iniContents = ''
    [OnlineSubsystemMcp.BaseServiceMcp]
    Protocol=https
    Domain=${masterServerDomain}
    EngineName=UE4
    ServiceName=entitlement
    GameName=UnrealTournament

    [OnlineSubsystemMcp.GameServiceMcp]
    Protocol=https
    Domain=${masterServerDomain}
    ServiceName=ut
    GameName=UnrealTournament

    [OnlineSubsystemMcp.AccountServiceMcp]
    Protocol=https
    Domain=${masterServerDomain}
    ServiceName=account
    GameName=UnrealTournament

    [OnlineSubsystemMcp.OnlineFriendsMcp]
    Protocol=https
    Domain=${masterServerDomain}
    ServiceName=friends
    GameName=UnrealTournament

    [OnlineSubsystemMcp.PersonaServiceMcp]
    Domain=${masterServerDomain}

    [OnlineSubsystemMcp.OnlineImageServiceMcp]
    Protocol=https
    Domain=${masterServerDomain}

    [OnlineSubsystemMcp.ContentControlsServiceMcp]
    Protocol=https
    Domain=${masterServerDomain}
  '';
  templateFile = pkgs.writeText "Engine.ini.template" iniContents;
in
pkgs.runCommand "ut4-engine-ini-template" { } ''
  mkdir -p $out
  install -m 644 ${templateFile} $out/Engine.ini.template
''
