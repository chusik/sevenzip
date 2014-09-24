unit SevenZipAdv;

{$mode delphi}

interface

uses
  Classes, SysUtils, SevenZip, JclCompression;

type
  TBytes = array of Byte;
  TJclCompressionArchiveClassArray = array of TJclCompressionArchiveClass;

type

   { TArchiveFormat }

   TArchiveFormat = class
     Name: UnicodeString;
     Extension: UnicodeString;
     AddExtension: UnicodeString;
     Update: WordBool;
     KeepName: WordBool;
     ClassID: TGUID;
     StartSignature: TBytes;
   end;

  { TJclSevenzipDecompressArchiveHelper }

  TJclSevenzipDecompressArchiveHelper = class helper for TJclSevenzipDecompressArchive
    procedure ExtractItem(Index: Cardinal; const ADestinationDir: UTF8String; Verify: Boolean);
  end;

function FindUpdateFormats(const AFileName: TFileName): TJclUpdateArchiveClassArray;
function FindCompressFormats(const AFileName: TFileName): TJclCompressArchiveClassArray;
function FindDecompressFormats(const AFileName: TFileName): TJclDecompressArchiveClassArray;

implementation

uses
  ActiveX, Windows, JclSysUtils, LazFileUtils;

type
  TArchiveFormats = array of TArchiveFormat;
  TJclSevenzipUpdateArchiveClass = class of TJclSevenzipUpdateArchive;
  TJclSevenzipCompressArchiveClass = class of TJclSevenzipCompressArchive;
  TJclSevenzipDecompressArchiveClass = class of TJclSevenzipDecompressArchive;
  TJclArchiveType = (atUpdateArchive, atCompressArchive, atDecompressArchive);

type
  TArchiveFormatCache = record
    ArchiveName: UTF8String;
    ArchiveClassArray: TJclCompressionArchiveClassArray;
  end;

var
  ArchiveFormatsX: TArchiveFormats;

var
  UpdateFormatsCache: TArchiveFormatCache;
  CompressFormatsCache: TArchiveFormatCache;
  DecompressFormatsCache: TArchiveFormatCache;

function ReadStringProp(FormatIndex: Cardinal; PropID: TPropID;
  out Value: UnicodeString): LongBool;
var
  PropSize: Cardinal;
  PropValue: TPropVariant;
begin
  Result:= Succeeded(GetHandlerProperty2(FormatIndex, PropID, PropValue));
  Result:= Result and (PropValue.vt = VT_BSTR);
  if Result then
  try
    PropSize:= SysStringByteLen(PropValue.bstrVal);
    SetLength(Value, PropSize div SizeOf(WideChar));
    CopyMemory(PWideChar(Value), PropValue.bstrVal, PropSize);
  finally
    SysFreeString(PropValue.bstrVal);
  end;
end;

function ReadBooleanProp(FormatIndex: Cardinal;
  PropID: TPropID; out Value: WordBool): LongBool;
var
  PropSize: Cardinal;
  PropValue: TPropVariant;
begin
  Result:= Succeeded(GetHandlerProperty2(FormatIndex, PropID, PropValue));
  Result:= Result and (PropValue.vt = VT_BOOL);
  if Result then Value:= PropValue.boolVal;
end;

procedure LoadArchiveFormats(var ArchiveFormats: TArchiveFormats);
var
  J: Integer;
  Data: PByte;
  Idx: Integer = 0;
  PropValue: TPropVariant;
  ArchiveFormat: TArchiveFormat;
  Index, NumberOfFormats: Cardinal;
begin
  if (not Is7ZipLoaded) and (not Load7Zip) then Exit;

  if not Succeeded(GetNumberOfFormats(@NumberOfFormats)) then
    Exit;
  SetLength(ArchiveFormats, NumberOfFormats);
  for Index := Low(ArchiveFormats) to High(ArchiveFormats) do
  begin
    // Archive format GUID
    GetHandlerProperty2(Index, kClassID, PropValue);
    if PropValue.vt = VT_BSTR then
    try
      if SysStringByteLen(PropValue.bstrVal) <> SizeOf(TGUID) then
        Continue
      else begin
        ArchiveFormat:= TArchiveFormat.Create;
        ArchiveFormat.ClassID:= PGUID(PropValue.bstrVal)^;
      end;
    finally
      SysFreeString(PropValue.bstrVal);
    end;
    // Archive format signature
    GetHandlerProperty2(Index, kStartSignature, PropValue);
    if PropValue.vt = VT_BSTR then
    try
      SetLength(ArchiveFormat.StartSignature, SysStringByteLen(PropValue.bstrVal));
      Data:= PByte(PropValue.bstrVal);
      for J:= Low(ArchiveFormat.StartSignature) to High(ArchiveFormat.StartSignature) do
       ArchiveFormat.StartSignature[J]:= Data[J];
    finally
      SysFreeString(PropValue.bstrVal);
    end;

    ReadStringProp(Index, kArchiveName, ArchiveFormat.Name);
    ReadStringProp(Index, kExtension, ArchiveFormat.Extension);
    ReadStringProp(Index, kAddExtension, ArchiveFormat.AddExtension);
    ReadBooleanProp(Index, kUpdate, ArchiveFormat.Update);
    ReadBooleanProp(Index, kKeepName, ArchiveFormat.KeepName);

    ArchiveFormats[Idx]:= ArchiveFormat;
    Inc(Idx);
  end;
  SetLength(ArchiveFormats, Idx);
end;

function Contains(const ArrayToSearch: TJclCompressionArchiveClassArray; const ArchiveClass: TJclCompressionArchiveClass): Boolean;
var
  Index: Integer;
begin
  for Index := Low(ArrayToSearch) to High(ArrayToSearch) do
    if ArrayToSearch[Index] = ArchiveClass then
      Exit(True);
  Result := False;
end;

function FindArchiveFormat(const ClassID: TGUID; ArchiveType: TJclArchiveType): TJclCompressionArchiveClass;
var
  Index: Integer;
  UpdateClass: TJclSevenzipUpdateArchiveClass;
  CompressClass: TJclSevenzipCompressArchiveClass;
  DecompressClass: TJclSevenzipDecompressArchiveClass;
begin
  case ArchiveType of
    atUpdateArchive:
      for Index:= 0 to GetArchiveFormats.UpdateFormatCount - 1 do
      begin
        UpdateClass:= TJclSevenzipUpdateArchiveClass(GetArchiveFormats.UpdateFormats[Index]);
        if GUIDEquals(ClassID, UpdateClass.ArchiveCLSID) then
          Exit(GetArchiveFormats.UpdateFormats[Index]);
      end;
    atCompressArchive:
      for Index:= 0 to GetArchiveFormats.CompressFormatCount - 1 do
      begin
        CompressClass:= TJclSevenzipCompressArchiveClass(GetArchiveFormats.CompressFormats[Index]);
        if GUIDEquals(ClassID, CompressClass.ArchiveCLSID) then
          Exit(GetArchiveFormats.CompressFormats[Index]);
      end;
    atDecompressArchive:
      for Index:= 0 to GetArchiveFormats.DecompressFormatCount - 1 do
      begin
        DecompressClass:= TJclSevenzipDecompressArchiveClass(GetArchiveFormats.DecompressFormats[Index]);
        if GUIDEquals(ClassID, DecompressClass.ArchiveCLSID) then
          Exit(GetArchiveFormats.DecompressFormats[Index]);
      end;
  end;
  Result:= nil;
end;

procedure FindArchiveFormats(const AFileName: TFileName; ArchiveType: TJclArchiveType; var Result: TJclCompressionArchiveClassArray);
const
  BufferSize = 524288;
var
  AFile: THandle;
  Idx, Index: Integer;
  ArchiveFormat: TArchiveFormat;
  ArchiveClass: TJclCompressionArchiveClass;
  Buffer: array[0..Pred(BufferSize)] of Byte;
begin
  if Length(ArchiveFormatsX) = 0 then LoadArchiveFormats(ArchiveFormatsX);

    AFile:= FileOpenUTF8(AFileName, fmOpenRead or fmShareDenyNone);
    if AFile = feInvalidHandle then Exit;
    try
     if FileRead(AFile, Buffer, SizeOf(Buffer)) = 0 then
       Exit;
    finally
      FileClose(AFile);
    end;

    for Index := Low(ArchiveFormatsX) to High(ArchiveFormatsX) do
    begin
      ArchiveFormat:= ArchiveFormatsX[Index];

      if (not ArchiveFormat.Update) and (ArchiveType in [atUpdateArchive, atCompressArchive]) then
        Continue;

      // Skip container types
      if GUIDEquals(ArchiveFormat.ClassID, CLSID_CFormatPe) then Continue;
      if GUIDEquals(ArchiveFormat.ClassID, CLSID_CFormatIso) then Continue;
      if GUIDEquals(ArchiveFormat.ClassID, CLSID_CFormatUdf) then Continue;

      if Length(ArchiveFormat.StartSignature) = 0 then Continue;
      for Idx:= 0 to Pred(BufferSize) - Length(ArchiveFormat.StartSignature) do
      begin
        if CompareMem(@Buffer[Idx], @ArchiveFormat.StartSignature[0], Length(ArchiveFormat.StartSignature)) then
        begin
          ArchiveClass:= FindArchiveFormat(ArchiveFormat.ClassID, ArchiveType);
          if Assigned(ArchiveClass) and not Contains(Result, ArchiveClass) then
          begin
            SetLength(Result, Length(Result) + 1);
            Result[High(Result)] := ArchiveClass;
          end;
          Break;
        end;
      end;
    end;
end;

function FindUpdateFormats(const AFileName: TFileName): TJclUpdateArchiveClassArray;
var
  ArchiveClassArray: TJclCompressionArchiveClassArray absolute Result;
begin
  // Try to find archive type in cache
  if UpdateFormatsCache.ArchiveName = AFileName then
    Exit(TJclUpdateArchiveClassArray(DecompressFormatsCache.ArchiveClassArray))
  else begin
    UpdateFormatsCache.ArchiveName:= AFileName;
    SetLength(UpdateFormatsCache.ArchiveClassArray, 0);
  end;

  Result:= GetArchiveFormats.FindUpdateFormats(AFileName);

  FindArchiveFormats(AFileName, atUpdateArchive, ArchiveClassArray);

  // Save archive type in cache
  UpdateFormatsCache.ArchiveClassArray:= ArchiveClassArray;
end;

function FindCompressFormats(const AFileName: TFileName): TJclCompressArchiveClassArray;
var
  ArchiveClassArray: TJclCompressionArchiveClassArray absolute Result;
begin
  // Try to find archive type in cache
  if CompressFormatsCache.ArchiveName = AFileName then
    Exit(TJclCompressArchiveClassArray(DecompressFormatsCache.ArchiveClassArray))
  else begin
    CompressFormatsCache.ArchiveName:= AFileName;
    SetLength(CompressFormatsCache.ArchiveClassArray, 0);
  end;

  Result:= GetArchiveFormats.FindCompressFormats(AFileName);

  FindArchiveFormats(AFileName, atCompressArchive, ArchiveClassArray);

  // Save archive type in cache
  CompressFormatsCache.ArchiveClassArray:= ArchiveClassArray;
end;

function FindDecompressFormats(const AFileName: TFileName): TJclDecompressArchiveClassArray;
var
  ArchiveClassArray: TJclCompressionArchiveClassArray absolute Result;
begin
  // Try to find archive type in cache
  if DecompressFormatsCache.ArchiveName = AFileName then
    Exit(TJclDecompressArchiveClassArray(DecompressFormatsCache.ArchiveClassArray))
  else begin
    DecompressFormatsCache.ArchiveName:= AFileName;
    SetLength(DecompressFormatsCache.ArchiveClassArray, 0);
  end;

  Result:= GetArchiveFormats.FindDecompressFormats(AFileName);

  FindArchiveFormats(AFileName, atDecompressArchive, ArchiveClassArray);

  // Save archive type in cache
  DecompressFormatsCache.ArchiveClassArray:= ArchiveClassArray;
end;

{ TJclSevenzipDecompressArchiveHelper }

procedure TJclSevenzipDecompressArchiveHelper.ExtractItem(Index: Cardinal; const ADestinationDir: UTF8String; Verify: Boolean);
var
  AExtractCallback: IArchiveExtractCallback;
begin
  CheckNotDecompressing;

  FDecompressing := True;
  FDestinationDir := ADestinationDir;
  AExtractCallback := TJclSevenzipExtractCallback.Create(Self);
  try
    OpenArchive;

    SevenzipCheck(InArchive.Extract(@Index, 1, Cardinal(Verify), AExtractCallback));
    CheckOperationSuccess;
  finally
    FDestinationDir := '';
    FDecompressing := False;
    AExtractCallback := nil;
  end;
end;

end.

