; The Windows installer (Inno Setup 6.3 or later), built by scripts/build-windows.ps1
; with /DVersion=X.Y.Z /DDist=<the build's dist directory>.
;
; It does what MSKLC's installers did: copies the layout's DLL into the system
; directories and registers it under the first free layout ID of German (Germany),
; A0000407 to AFFF0407; an update keeps the ID it has. A task adds it to the
; keyboards of the person installing, as MSKLC's installers did too.

#ifndef Version
  #define Version "0.0.0"
#endif
#ifndef Dist
  #define Dist "..\dist"
#endif
#define Name "Polish (Germany, no dead keys)"

[Setup]
AppId={{6E2C5B8A-3F0D-4D9B-9E4A-1C7A2F5D8B31}
AppName={#Name} keyboard layout
AppVersion={#Version}
AppPublisher=Dawid Ciepiela
AppPublisherURL=https://git.ciepiela.org/dawid/depl-keyboard-layout
DefaultDirName={autopf}\depl-keyboard-layout
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=admin
; kbdutool builds no ARM64 DLL, and an x64 one does not load in ARM64 programs.
ArchitecturesAllowed=x86os or x64os
ArchitecturesInstallIn64BitMode=x64os
LicenseFile=..\LICENSE
OutputDir={#Dist}
OutputBaseFilename=depl-setup
UninstallDisplayName={#Name} keyboard layout
WizardStyle=modern
SetupLogging=yes

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "de"; MessagesFile: "compiler:Languages\German.isl"
Name: "pl"; MessagesFile: "compiler:Languages\Polish.isl"

[CustomMessages]
en.AddLayout=Add the layout to my keyboards
de.AddLayout=Das Layout zu meinen Tastaturen hinzufügen
pl.AddLayout=Dodaj układ do moich klawiatur

[Tasks]
Name: "addlayout"; Description: "{cm:AddLayout}"

[Files]
Source: "{#Dist}\windows\amd64\depl.dll"; DestDir: "{sys}"; Check: Is64BitInstallMode; \
  Flags: restartreplace uninsrestartdelete
Source: "{#Dist}\windows\wow64\depl.dll"; DestDir: "{syswow64}"; Check: Is64BitInstallMode; \
  Flags: restartreplace uninsrestartdelete 32bit
Source: "{#Dist}\windows\i386\depl.dll"; DestDir: "{sys}"; Check: not Is64BitInstallMode; \
  Flags: restartreplace uninsrestartdelete

[Registry]
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Keyboard Layouts\{code:Klid}"; \
  Flags: uninsdeletekey
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Keyboard Layouts\{code:Klid}"; \
  ValueType: string; ValueName: "Layout File"; ValueData: "depl.dll"
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Keyboard Layouts\{code:Klid}"; \
  ValueType: string; ValueName: "Layout Text"; ValueData: "{#Name}"
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Keyboard Layouts\{code:Klid}"; \
  ValueType: string; ValueName: "Layout Id"; ValueData: "{code:LayoutId}"

; The language list takes the layout as 0407:<its ID>; German is added to it
; where the person has no German yet.
[Run]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""$l = Get-WinUserLanguageList; $d = $l | Where-Object LanguageTag -eq 'de-DE'; if (-not $d) {{ $l.Add('de-DE'); $d = $l | Where-Object LanguageTag -eq 'de-DE' }; if ($d.InputMethodTips -notcontains '0407:{code:Klid}') {{ $d.InputMethodTips.Add('0407:{code:Klid}') }; Set-WinUserLanguageList $l -Force"""; \
  Flags: runhidden runasoriginaluser; Tasks: addlayout; StatusMsg: "{cm:AddLayout}"

[UninstallRun]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""$l = Get-WinUserLanguageList; foreach ($x in $l) {{ [void]$x.InputMethodTips.Remove('0407:{code:Klid}') }; Set-WinUserLanguageList $l -Force"""; \
  Flags: runhidden; RunOnceId: "RemoveLayout"

[Code]
const
  LayoutsKey = 'SYSTEM\CurrentControlSet\Control\Keyboard Layouts';

var
  TheKlid, TheLayoutId: String;

{ Finds the layout's ID where an earlier version registered it, or a free one. }
procedure ChooseIds();
var
  Names: TArrayOfString;
  I, Id: Integer;
  Value, Used: String;
begin
  if TheKlid <> '' then
    Exit;
  Used := ',';
  if RegGetSubkeyNames(HKLM, LayoutsKey, Names) then
    for I := 0 to GetArrayLength(Names) - 1 do
    begin
      if RegQueryStringValue(HKLM, LayoutsKey + '\' + Names[I], 'Layout File', Value)
        and (CompareText(Value, 'depl.dll') = 0) then
      begin
        TheKlid := Uppercase(Names[I]);
        RegQueryStringValue(HKLM, LayoutsKey + '\' + Names[I], 'Layout Id', TheLayoutId);
      end
      else if RegQueryStringValue(HKLM, LayoutsKey + '\' + Names[I], 'Layout Id', Value) then
        Used := Used + Lowercase(Value) + ',';
    end;
  if TheKlid = '' then
    for I := 0 to $FFF do
      if not RegKeyExists(HKLM, LayoutsKey + '\' + Format('a%.3x0407', [I])) then
      begin
        TheKlid := Uppercase(Format('a%.3x0407', [I]));
        Break;
      end;
  { Windows' own layouts take the low Layout Ids, MSKLC's begin at 00C0; above
    0FFF a layout is not shown. }
  if TheLayoutId = '' then
    for Id := $00C0 to $0FFF do
      if Pos(',' + Lowercase(Format('%.4x', [Id])) + ',', Used) = 0 then
      begin
        TheLayoutId := Lowercase(Format('%.4x', [Id]));
        Break;
      end;
  if (TheKlid = '') or (TheLayoutId = '') then
    RaiseException('No free keyboard layout ID is left.');
end;

function Klid(Param: String): String;
begin
  ChooseIds();
  Result := TheKlid;
end;

function LayoutId(Param: String): String;
begin
  ChooseIds();
  Result := TheLayoutId;
end;
