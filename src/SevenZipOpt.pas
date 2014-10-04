unit SevenZipOpt;

{$mode delphi}

interface

uses
  Classes, SysUtils, Windows, IniFiles;

const
  cKilo = 1024;
  cMega = cKilo * cKilo;
  cGiga = cKilo * cKilo * cKilo;

const
  DeflateDict: array[0..0] of Int64 =
  (
   cKilo * 32
  );

  Deflate64Dict: array[0..0] of Int64 =
  (
   cKilo * 64
  );

  Bzip2Dict: array[0..8] of Int64 =
  (
   cKilo * 100,
   cKilo * 200,
   cKilo * 300,
   cKilo * 400,
   cKilo * 500,
   cKilo * 600,
   cKilo * 700,
   cKilo * 800,
   cKilo * 900
  );

  LZMADict: array[0..12] of Int64 =
  (
   cKilo * 64,
   cMega,
   cMega * 2,
   cMega * 3,
   cMega * 4,
   cMega * 6,
   cMega * 8,
   cMega * 12,
   cMega * 16,
   cMega * 24,
   cMega * 32,
   cMega * 48,
   cMega * 64
  );

  PPMdDict: array[0..17] of Int64 =
  (
   cMega,
   cMega * 2,
   cMega * 3,
   cMega * 4,
   cMega * 6,
   cMega * 8,
   cMega * 12,
   cMega * 16,
   cMega * 24,
   cMega * 32,
   cMega * 48,
   cMega * 64,
   cMega * 96,
   cMega * 128,
   cMega * 192,
   cMega * 256,
   cMega * 384,
   cMega * 512
  );

  DeflateWordSize: array[0..11] of Int64 =
    (8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 258);

  Deflate64WordSize: array[0..11] of Int64 =
    (8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 257);

  LZMAWordSize: array[0..11] of Int64 =
    (8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 273);

  PPMdWordSize: array[0..14] of Int64 =
    (2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);

  SolidBlock: array[0..16] of Int64 =
  (
    cMega,
    cMega * 2,
    cMega * 4,
    cMega * 8,
    cMega * 16,
    cMega * 32,
    cMega * 64,
    cMega * 128,
    cMega * 256,
    cMega * 512,
    cGiga,
    cGiga * 2,
    cGiga * 4,
    cGiga * 8,
    cGiga * 16,
    cGiga * 32,
    cGiga * 64
  );

type

  TArchiveFormat = (afSevenZip, afBzip2, afGzip, afTar, afWim, afXz, afZip);
  TCompressionLevel = (clStore, clFastest, clFast, clNormal, clMaximum, clUltra);

  PPasswordData = ^TPasswordData;
  TPasswordData = record
    EncryptHeader: Boolean;
    Password: array[0..MAX_PATH] of WideChar;
  end;

  TFormatOptions = record
    Level: Integer;
    Method: Integer;
    Dictionary: Integer;
    WordSize: Integer;
    SolidSize: Integer;
    ThreadCount: Integer;
  end;

function GetNumberOfProcessors: LongWord;
function FormatFileSize(ASize: Int64): UTF8String;

procedure LoadConfiguration;
procedure SaveConfiguration;

var
  ConfigFile: AnsiString;

var
  PluginConfig: array[TArchiveFormat] of TFormatOptions =
  (
   (Level: 3; Method: 0; Dictionary: 8; WordSize: 4; SolidSize: 12; ThreadCount: 1;),
   (Level: 3; Method: 0; Dictionary: 8; WordSize: 4; SolidSize: 12; ThreadCount: 1;),
   (Level: 1; Method: 0; Dictionary: 0; WordSize: 4; SolidSize: 0; ThreadCount: 0;),
   (Level: 0; Method: 0; Dictionary: 8; WordSize: 4; SolidSize: 12; ThreadCount: 0;),
   (Level: 0; Method: 0; Dictionary: 8; WordSize: 4; SolidSize: 12; ThreadCount: 0;),
   (Level: 3; Method: 0; Dictionary: 8; WordSize: 4; SolidSize: 12; ThreadCount: 1;),
   (Level: 3; Method: 0; Dictionary: 0; WordSize: 4; SolidSize: 12; ThreadCount: 1;)
  );

implementation

uses
  TypInfo;

function GetNumberOfProcessors: LongWord;
var
  SystemInfo: TSYSTEMINFO;
begin
  GetSystemInfo(@SystemInfo);
  Result:= SystemInfo.dwNumberOfProcessors;
end;

function FormatFileSize(ASize: Int64): UTF8String;
begin
  if (ASize div cGiga) > 0 then
    Result:= IntToStr(ASize div cGiga) + 'Gb'
  else
  if (ASize div cMega) >0 then
    Result:= IntToStr(ASize div cMega) + 'Mb'
  else
  if (ASize div cKilo) > 0 then
    Result:= IntToStr(ASize div cKilo) + 'Kb'
  else
    Result:= IntToStr(ASize);
end;

procedure LoadConfiguration;
var
  Ini: TIniFile;
  Section: AnsiString;
  ArchiveFormat: TArchiveFormat;
begin
  try
    Ini:= TIniFile.Create(ConfigFile);
    try
      for ArchiveFormat:= Low(TArchiveFormat) to High(TArchiveFormat) do
      begin
        Section:= GetEnumName(TypeInfo(TArchiveFormat), Integer(ArchiveFormat));
        PluginConfig[ArchiveFormat].Level:= Ini.ReadInteger(Section, 'Level', PluginConfig[ArchiveFormat].Level);
        PluginConfig[ArchiveFormat].Method:= Ini.ReadInteger(Section, 'Method', PluginConfig[ArchiveFormat].Method);
        PluginConfig[ArchiveFormat].Dictionary:= Ini.ReadInteger(Section, 'Dictionary', PluginConfig[ArchiveFormat].Dictionary);
        PluginConfig[ArchiveFormat].WordSize:= Ini.ReadInteger(Section, 'WordSize', PluginConfig[ArchiveFormat].WordSize);
        PluginConfig[ArchiveFormat].SolidSize:= Ini.ReadInteger(Section, 'SolidSize', PluginConfig[ArchiveFormat].SolidSize);
        PluginConfig[ArchiveFormat].ThreadCount:= Ini.ReadInteger(Section, 'ThreadCount', PluginConfig[ArchiveFormat].ThreadCount);
      end;
    finally
      Ini.Free;
    end;
  except
    on E: Exception do
      MessageBox(0, PAnsiChar(E.Message), nil, MB_OK or MB_ICONERROR);
  end;
end;

procedure SaveConfiguration;
var
  Ini: TIniFile;
  Section: AnsiString;
  ArchiveFormat: TArchiveFormat;
begin
  try
    Ini:= TIniFile.Create(ConfigFile);
    try
      for ArchiveFormat:= Low(TArchiveFormat) to High(TArchiveFormat) do
      begin
        Section:= GetEnumName(TypeInfo(TArchiveFormat), Integer(ArchiveFormat));
        Ini.WriteInteger(Section, 'Level', PluginConfig[ArchiveFormat].Level);
        Ini.WriteInteger(Section, 'Method', PluginConfig[ArchiveFormat].Method);
        Ini.WriteInteger(Section, 'Dictionary', PluginConfig[ArchiveFormat].Dictionary);
        Ini.WriteInteger(Section, 'WordSize', PluginConfig[ArchiveFormat].WordSize);
        Ini.WriteInteger(Section, 'SolidSize', PluginConfig[ArchiveFormat].SolidSize);
        Ini.WriteInteger(Section, 'ThreadCount', PluginConfig[ArchiveFormat].ThreadCount);
      end;
    finally
      Ini.Free;
    end;
  except
    on E: Exception do
      MessageBox(0, PAnsiChar(E.Message), nil, MB_OK or MB_ICONERROR);
  end;
end;

end.
