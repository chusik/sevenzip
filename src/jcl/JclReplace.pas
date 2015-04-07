unit JclReplace;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fgl, Windows;

// JclBase.pas -----------------------------------------------------------------
type
  EJclError = class(Exception);
  TDynByteArray = array of Byte;
  TDynCardinalArray = array of Cardinal;

// JclStreams.pas --------------------------------------------------------------
type
  TJclStream = TStream;
  TJclOnVolume = function(Index: Integer): TStream of object;
  TJclOnVolumeMaxSize = function(Index: Integer): Int64 of object;

type

  { TJclDynamicSplitStream }

  TJclDynamicSplitStream = class(TJclStream)
  private
    FOnVolume: TJclOnVolume;
    FOnVolumeMaxSize: TJclOnVolumeMaxSize;
  public
    constructor Create(ADummy: Boolean = False);
    property OnVolume: TJclOnVolume read FOnVolume write FOnVolume;
    property OnVolumeMaxSize: TJclOnVolumeMaxSize read FOnVolumeMaxSize write FOnVolumeMaxSize;
  end;

  function StreamCopy(Source, Target: TStream): Int64;

// JclDateTime.pas -------------------------------------------------------------
function LocalDateTimeToFileTime(DateTime: TDateTime): TFileTime;

// JclFileUtils.pas ------------------------------------------------------------
const
  DirDelimiter = DirectorySeparator;
  DirSeparator = PathSeparator;

type
  TJclOnAddDirectory = procedure(const Directory: String) of object;
  TJclOnAddFile = procedure(const Directory: String; const FileInfo: TSearchRec) of object;

function PathAddSeparator(const Path: String): String;
function PathRemoveSeparator(const Path: String): String;
function PathGetRelativePath(const Base, Path: String): String;

function PathCanonicalize(const Path: WideString): WideString;
function IsFileNameMatch(const FileName, Mask: WideString): Boolean;

procedure BuildFileList(const SourceFile: String; FileAttr: Integer; InnerList: TStrings; Dummy: Boolean);
procedure EnumFiles(const Path: String; OnAddFile: TJclOnAddFile; ExcludeAttributes: Integer);
procedure EnumDirectories(const Path: String; OnAddDirectory: TJclOnAddDirectory;
                          DummyBoolean: Boolean; const DummyString: String; DummyPointer: Pointer);

function FindUnusedFileName(const FileName, FileExt: String): String;

// JclSysUtils.pas -------------------------------------------------------------
function GUIDEquals(const GUID1, GUID2: TGUID): Boolean; inline;

// JclStrings.pas --------------------------------------------------------------
procedure StrTokenToStrings(const Token: String; Separator: AnsiChar; var Strings: TStrings);

// JclWideStrings.pas

type
  TFPWideStrObjMap = specialize TFPGMap<WideString, TObject>;

type

  { TJclWideStringList }

  TJclWideStringList = class(TPersistent)
  private
    FMap: TFPWideStrObjMap;
    FCaseSensitive: Boolean;
  private
    function GetDuplicates: TDuplicates;
    function GetSorted: Boolean;
    procedure SetCaseSensitive(AValue: Boolean);
    procedure SetDuplicates(AValue: TDuplicates);
    procedure SetSorted(AValue: Boolean);
  protected
    function Get(Index: Integer): WideString;
    function GetObject(Index: Integer): TObject;
    procedure Error(const Msg: String; Data: Integer);
    procedure Put(Index: Integer; const S: WideString);
    procedure PutObject(Index: Integer; AObject: TObject);
    function CompareWideStringProc(Key1, Key2: Pointer): Integer;
    function CompareTextWideStringProc(Key1, Key2: Pointer): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Delete(Index: Integer);
    function Add(const S: WideString): Integer;
    function AddObject(const S: WideString; AObject: TObject): Integer;
    function Find(const S: WideString; var Index: Integer): Boolean;
    function IndexOf(const S: WideString): Integer;

    property Duplicates: TDuplicates read GetDuplicates write SetDuplicates;
    property Sorted: Boolean read GetSorted write SetSorted;
    property CaseSensitive: Boolean read FCaseSensitive write SetCaseSensitive;
    property Objects[Index: Integer]: TObject read GetObject write PutObject;
    property Strings[Index: Integer]: WideString read Get write Put; default;
  end;

implementation

uses
  RtlConsts;

function StreamCopy(Source, Target: TStream): Int64;
begin
  Result:= Target.CopyFrom(Source, Source.Size);
end;

function LocalDateTimeToFileTime(DateTime: TDateTime): TFileTime;
begin
  Int64(Result) := Round((Extended(DateTime) + 109205.0) * 864000000000.0);
  Windows.LocalFileTimeToFileTime(@Result, @Result);
end;

function PathAddSeparator(const Path: String): String;
begin
  Result:= IncludeTrailingPathDelimiter(Path);
end;

function PathRemoveSeparator(const Path: String): String;
begin
  Result:= ExcludeTrailingPathDelimiter(Path);
end;

function PathGetRelativePath(const Base, Path: String): String;
begin
  Result:= ExtractRelativePath(Base, Path);
end;

function PathMatchSpecW(pszFile, pszSpec: LPCWSTR): BOOL; stdcall; external 'shlwapi.dll';
function PathCanonicalizeW(lpszDst, lpszSrc: LPCWSTR): BOOL; stdcall; external 'shlwapi.dll';

function PathCanonicalize(const Path: WideString): WideString;
begin
  SetLength(Result, MAX_PATH);
  if PathCanonicalizeW(PWideChar(Result), PWideChar(Path)) then
    Result:= PWideChar(Result)
  else begin
    Result:= EmptyWideStr;
  end;
end;

function IsFileNameMatch(const FileName, Mask: WideString): Boolean;
begin
  Result:= PathMatchSpecW(PWideChar(FileName), PWideChar(Mask));
end;

procedure BuildFileList(const SourceFile: String; FileAttr: Integer;
                        InnerList: TStrings; Dummy: Boolean);
begin
  raise Exception.Create('BuildFileList');
end;

procedure EnumFiles(const Path: String; OnAddFile: TJclOnAddFile; ExcludeAttributes: Integer);
begin
  raise Exception.Create('EnumFiles');
end;

procedure EnumDirectories(const Path: String; OnAddDirectory: TJclOnAddDirectory;
                          DummyBoolean: Boolean; const DummyString: String; DummyPointer: Pointer);
begin
  raise Exception.Create('EnumDirectories');
end;

function FindUnusedFileName(const FileName, FileExt: String): String;
var
  Counter: Int64 = 0;
begin
  Result:= FileName + ExtensionSeparator + FileExt;
  if FileExists(Result) then
  repeat
    Inc(Counter);
    Result:= FileName + IntToStr(Counter) + ExtensionSeparator + FileExt;
  until not FileExists(Result);
end;

function GUIDEquals(const GUID1, GUID2: TGUID): Boolean;
begin
  Result:= IsEqualGUID(GUID1, GUID2);
end;

procedure StrTokenToStrings(const Token: String; Separator: AnsiChar; var Strings: TStrings);
var
  Start: Integer = 1;
  Len, Finish: Integer;
begin
  Len:= Length(Token);
  Strings.BeginUpdate;
  try
    Strings.Clear;
    for Finish:= 1 to Len - 1 do
    begin
      if Token[Finish] = Separator then
      begin
        Strings.Add(Copy(Token, Start, Finish - Start));
        Start:= Finish + 1;
      end;
    end;
    if Start <= Len then
    begin
      Strings.Add(Copy(Token, Start, Len - Start + 1));
    end;
  finally
    Strings.EndUpdate;
  end;
end;

{ TJclDynamicSplitStream }

constructor TJclDynamicSplitStream.Create(ADummy: Boolean);
begin
  Create;
end;

{ TJclWideStringList }

function TJclWideStringList.GetDuplicates: TDuplicates;
begin
  Result := FMap.Duplicates;
end;

function TJclWideStringList.GetSorted: Boolean;
begin
  Result := FMap.Sorted;
end;

procedure TJclWideStringList.SetCaseSensitive(AValue: Boolean);
begin
  if FCaseSensitive <> AValue then
  begin
    FCaseSensitive:= AValue;
    if FCaseSensitive then
      FMap.OnKeyPtrCompare := @CompareWideStringProc
    else begin
      FMap.OnKeyPtrCompare := @CompareTextWideStringProc;
    end;
    if FMap.Sorted then FMap.Sort;
  end;
end;

procedure TJclWideStringList.SetDuplicates(AValue: TDuplicates);
begin
  FMap.Duplicates := AValue;
end;

procedure TJclWideStringList.SetSorted(AValue: Boolean);
begin
  FMap.Sorted := AValue;
end;

function TJclWideStringList.Get(Index: Integer): WideString;
begin
  Result := FMap.Keys[Index];
end;

function TJclWideStringList.GetObject(Index: Integer): TObject;
begin
  Result := FMap.Data[Index];
end;

procedure TJclWideStringList.Error(const Msg: String; Data: Integer);
begin
  raise EStringListError.CreateFmt(Msg, [Data]) at get_caller_addr(get_frame), get_caller_frame(get_frame);
end;

procedure TJclWideStringList.Put(Index: Integer; const S: WideString);
begin
  FMap.Keys[Index] := S;
end;

procedure TJclWideStringList.PutObject(Index: Integer; AObject: TObject);
begin
  FMap.Data[Index] := AObject;
end;

function TJclWideStringList.CompareWideStringProc(Key1, Key2: Pointer): Integer;
begin
  Result:= WideStringManager.CompareWideStringProc(WideString(Key1^), WideString(Key2^));
end;

function TJclWideStringList.CompareTextWideStringProc(Key1, Key2: Pointer): Integer;
begin
  Result:= WideStringManager.CompareTextWideStringProc(WideString(Key1^), WideString(Key2^));
end;

constructor TJclWideStringList.Create;
begin
  FMap := TFPWideStrObjMap.Create;
  FMap.OnPtrCompare := @CompareTextWideStringProc;
end;

destructor TJclWideStringList.Destroy;
begin
  FMap.Free;
  inherited Destroy;
end;

procedure TJclWideStringList.Delete(Index: Integer);
begin
  if (Index < 0) or (Index >= FMap.Count) then
    Error(SListIndexError, Index);
  FMap.Delete(Index);
end;

function TJclWideStringList.Add(const S: WideString): Integer;
begin
  Result := FMap.Add(S);
end;

function TJclWideStringList.AddObject(const S: WideString; AObject: TObject): Integer;
begin
  Result:= Add(S);
  Objects[Result]:= AObject;
end;

function TJclWideStringList.Find(const S: WideString; var Index: Integer): Boolean;
begin
  Result := FMap.Find(S, Index);
end;

function TJclWideStringList.IndexOf(const S: WideString): Integer;
begin
  Result := FMap.IndexOf(S);
end;

end.

