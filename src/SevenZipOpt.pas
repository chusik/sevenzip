unit SevenZipOpt;

{$mode delphi}

interface

uses
  Classes, SysUtils, Windows;

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

function GetNumberOfProcessors: LongWord;
function FormatFileSize(ASize: Int64): UTF8String;

implementation


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

end.

