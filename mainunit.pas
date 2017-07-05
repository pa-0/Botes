unit mainunit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, SynEdit, SynHighlighterAny, Forms, Controls,
  Graphics, Dialogs, StdCtrls, Menus, ExtCtrls, ComCtrls, ActnList,
  SynEditMarkupHighAll, SynEditMiscClasses, SynEditMarkupSpecialLine, StrUtils;

type

  { TForm1 }


  TForm1 = class(TForm)
    BeginFindAction: TAction;
    TextQueryStatusLabel: TLabel;
    TextQueryPanel: TPanel;
    SaveNotesAction: TAction;
    MoveTabForwardAction: TAction;
    MoveTabBackwardAction: TAction;
    PrevTabAction: TAction;
    NextTabAction: TAction;
    NewTabAction: TAction;
    CloseTabAction: TAction;
    MainTabsActionList: TActionList;
    AwesomeBar: TEdit;
    MainTabs: TTabControl;
    TextQuery: TEdit;
    Suggestions: TMemo;
    TextEditor: TSynEdit;
    procedure AwesomeBarChange(Sender: TObject);
    procedure AwesomeBarEnter(Sender: TObject);
    procedure AwesomeBarExit(Sender: TObject);
    procedure AwesomeBarKeyPress(Sender: TObject; var Key: char);
    procedure BeginFindActionExecute(Sender: TObject);
    procedure CloseTabActionExecute(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure MainTabsChange(Sender: TObject);
    procedure MainTabsChanging(Sender: TObject; var AllowChange: boolean);
    procedure MoveTabBackwardActionExecute(Sender: TObject);
    procedure MoveTabForwardActionExecute(Sender: TObject);
    procedure NewTabActionExecute(Sender: TObject);
    procedure NextTabActionExecute(Sender: TObject);
    procedure PrevTabActionExecute(Sender: TObject);
    procedure SaveNotesActionExecute(Sender: TObject);
    procedure TextEditorKeyPress(Sender: TObject; var Key: char);
    procedure TextEditorSpecialLineMarkup(Sender: TObject; Line: integer;
      var Special: boolean; Markup: TSynSelectedColor);
    procedure TextQueryChange(Sender: TObject);
    procedure TextQueryEnter(Sender: TObject);
    procedure TextQueryExit(Sender: TObject);
    procedure TextQueryKeyPress(Sender: TObject; var Key: char);
  private
    FAllLines, FDiscardedLines, FAllTags: TStringList;
    FFoundTextPoints: array of TPoint; //xy of caret for each found text

    procedure CollectAllTags;
    procedure FilterTextByAwesomeBar;
    procedure UpdateSuggestions;
    procedure SaveNotes;
    function QueryUnsavedChanges: TModalResult;
    procedure RefreshFoundPoints;
    procedure MoveCursorToNextFind;
    { private declarations }
  public
    { public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

function IsTagLine(const line: string): boolean;
begin
  Result := line.StartsWith('#');
end;

procedure TForm1.FormCreate(Sender: TObject);
var
  markup: TSynEditMarkupHighlightAllCaret;
  i: integer;
begin
  FAllLines := TStringList.Create;
  FAllLines.LineBreak := #10;
  FDiscardedLines := TStringList.Create;
  FDiscardedLines.LineBreak := #10;
  FAllTags := TStringList.Create;
  FAllLines.LineBreak := #10;
  MainTabs.Tabs.LineBreak := #10;

  try
    FAllLines.LoadFromFile(ExtractFilePath(Application.ExeName) + 'allnotes.txt');
  except
    on EFOpenError do
      MessageDlg('File not found', 'Failed to open file allnotes.txt.',
        mtError, [mbOK], 0);
  end;

  FAllTags.Sorted := True;
  FAllTags.Duplicates := dupIgnore;
  CollectAllTags;

  TextEditor.Lines.Assign(FAllLines);

  markup := TSynEditMarkupHighlightAllCaret(
    TextEditor.MarkupByClass[TSynEditMarkupHighlightAllCaret]);
  markup.MarkupInfo.FrameColor := clSilver;
  markup.MarkupInfo.Background := clGray;
  markup.WaitTime := 100;
  markup.Trim := True;
  markup.FullWord := True;

  try
    MainTabs.Tabs.LoadFromFile(ExtractFilePath(Application.ExeName) + 'tabs.txt');
    for i := 0 to MainTabs.Tabs.Count - 1 do
      if (length(MainTabs.Tabs[i]) > 0) and (MainTabs.Tabs[i][1] = '@') then
      begin
        MainTabs.Tabs[i] := Copy(MainTabs.Tabs[i], 2, length(MainTabs.Tabs[i]));
        MainTabs.TabIndex := i;
      end;
  except
    //ignore EFOpenError - we start with one empty tab set in designer so its ok
  end;

  //set first tab awesome bar
  MainTabsChange(MainTabs);
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  FAllLines.Free;
  FDiscardedLines.Free;
  FAllTags.Free;
end;

procedure TForm1.FormShow(Sender: TObject);
begin
  WindowState := wsMaximized;

  //set focus to text if there is a tag query or to awesome bar if there isnt
  if Length(MainTabs.Tabs[MainTabs.TabIndex]) = 0 then
    AwesomeBar.SetFocus
  else
    TextEditor.SetFocus;
end;

procedure TForm1.MainTabsChange(Sender: TObject);
begin
  AwesomeBar.Text := MainTabs.Tabs[MainTabs.TabIndex];
end;

procedure TForm1.MainTabsChanging(Sender: TObject; var AllowChange: boolean);
var
  ans: TModalResult;
begin
  if TextEditor.Modified then
  begin
    ans := QueryUnsavedChanges;
    if ans = mrCancel then
      AllowChange := False;

    if ans = mrYes then
      SaveNotes;

    if ans = mrNo then
      TextEditor.Modified := False;

  end; //if
end;

procedure TForm1.MoveTabBackwardActionExecute(Sender: TObject);
var
  onchanging: TTabChangingEvent;
begin
  if MainTabs.TabIndex = 0 then
    Exit;

  MainTabs.Tabs.Exchange(MainTabs.TabIndex, MainTabs.TabIndex - 1);
  onchanging := MainTabs.OnChanging;
  MainTabs.OnChanging := nil;
  MainTabs.TabIndex := MainTabs.TabIndex - 1;
  MainTabs.OnChanging := onchanging;
end;

procedure TForm1.MoveTabForwardActionExecute(Sender: TObject);
var
  onchanging: TTabChangingEvent;
begin
  if (MainTabs.TabIndex + 1) = MainTabs.Tabs.Count then
    Exit;

  MainTabs.Tabs.Exchange(MainTabs.TabIndex, MainTabs.TabIndex + 1);
  onchanging := MainTabs.OnChanging;
  MainTabs.OnChanging := nil;
  MainTabs.TabIndex := MainTabs.TabIndex + 1;
  MainTabs.OnChanging := onchanging;
end;

procedure TForm1.NewTabActionExecute(Sender: TObject);
begin
  MainTabs.Tabs.Append('');
  MainTabs.TabIndex := MainTabs.Tabs.Count - 1;
  AwesomeBar.SetFocus;
end;

procedure TForm1.NextTabActionExecute(Sender: TObject);
var
  tab: integer;
begin
  tab := MainTabs.TabIndex + 1;
  if tab = MainTabs.Tabs.Count then
    tab := 0;

  MainTabs.TabIndex := tab;
end;

procedure TForm1.PrevTabActionExecute(Sender: TObject);
var
  tab: integer;
begin
  tab := MainTabs.TabIndex;
  if tab = 0 then
    tab := MainTabs.Tabs.Count;

  MainTabs.TabIndex := tab - 1;
end;

procedure TForm1.SaveNotesActionExecute(Sender: TObject);
begin
  SaveNotes;
end;

procedure TForm1.TextEditorKeyPress(Sender: TObject; var Key: char);
begin
  if Ord(Key) = 27 then
    AwesomeBar.SetFocus;
end;

procedure TForm1.TextEditorSpecialLineMarkup(Sender: TObject;
  Line: integer; var Special: boolean; Markup: TSynSelectedColor);
begin
  if IsTagLine(TextEditor.Lines[Line - 1]) then
  begin
    Special := True;
    Markup.Background := clMoneyGreen;
    Markup.Foreground := clBlack;
  end;
end;

procedure TForm1.TextQueryChange(Sender: TObject);
begin
  RefreshFoundPoints;
end;

procedure TForm1.TextQueryEnter(Sender: TObject);
begin
  RefreshFoundPoints;
  MoveCursorToNextFind;
end;

procedure TForm1.TextQueryExit(Sender: TObject);
begin
  TextQueryPanel.Hide;
end;

procedure TForm1.TextQueryKeyPress(Sender: TObject; var Key: char);
begin
  if Ord(Key) = 27 then
    TextEditor.SetFocus;

  if Ord(Key) = 13 then
    MoveCursorToNextFind;
end;

procedure TForm1.AwesomeBarChange(Sender: TObject);
begin
  MainTabs.Tabs[MainTabs.TabIndex] := AwesomeBar.Text;
  UpdateSuggestions;
  if AwesomeBar.Text = '' then
  begin
    FDiscardedLines.Clear;
    TextEditor.Lines.Assign(FAllLines);
  end
  else
    FilterTextByAwesomeBar;
end;

procedure TForm1.AwesomeBarEnter(Sender: TObject);
var
  ans: TModalResult;
begin
  if TextEditor.Modified then
  begin
    ans := QueryUnsavedChanges;
    if ans = mrCancel then
      Exit;

    if ans = mrYes then
      SaveNotes;
  end;

  Suggestions.Visible := True;
  UpdateSuggestions;
end;

procedure TForm1.AwesomeBarExit(Sender: TObject);
begin
  Suggestions.Visible := False;
end;

procedure TForm1.AwesomeBarKeyPress(Sender: TObject; var Key: char);
begin
  if (Ord(Key) = 27) or (Ord(Key) = 13) then
    TextEditor.SetFocus;
end;

procedure TForm1.BeginFindActionExecute(Sender: TObject);
begin
  TextQueryPanel.Show;
  TextQuery.SetFocus;
end;

procedure TForm1.CloseTabActionExecute(Sender: TObject);
begin
  MainTabs.Tabs.Delete(MainTabs.TabIndex);
  if MainTabs.Tabs.Count = 0 then
  begin
    MainTabs.Tabs.Append('');
    MainTabsChange(MainTabs);
  end;
end;

procedure TForm1.FormClose(Sender: TObject; var CloseAction: TCloseAction);
var
  strs: TStringList;
begin
  strs := TStringList.Create;
  strs.Assign(MainTabs.Tabs);
  strs[MainTabs.TabIndex] := '@' + strs[MainTabs.TabIndex];
  strs.SaveToFile(ExtractFilePath(Application.ExeName) + 'tabs.txt');
  strs.Free;
end;

procedure TForm1.FormCloseQuery(Sender: TObject; var CanClose: boolean);
var
  ans: TModalResult;
begin
  if not TextEditor.Modified then
  begin
    CanClose := True;
    Exit;
  end;

  ans := QueryUnsavedChanges;
  CanClose := (ans <> mrCancel);
  if ans = mrYes then
    SaveNotes;
end;

procedure TForm1.CollectAllTags;
var
  str: string;
  split: TStringList;
begin
  FAllTags.Clear;
  split := TStringList.Create;
  try
    split.Delimiter := ' ';
    for str in FAllLines do
      if IsTagLine(str) then
      begin
        split.Clear;
        split.DelimitedText := str.Replace('#', '');
        FAllTags.AddStrings(split);
      end;
  finally
    split.Free;
  end;
end;

procedure TForm1.FilterTextByAwesomeBar;
var
  str: string;
  inseg: boolean;
  tmp: TStringList;
begin
  try
    tmp := TStringList.Create;
    TextEditor.Lines.Clear;
    FDiscardedLines.Clear;
    inseg := False;
    for str in FAllLines do
    begin
      if IsTagLine(str) then
        inseg := (str + ' ').Contains('#' + AwesomeBar.Text + ' ');

      if inseg then
        tmp.Add(str)
      else
        FDiscardedLines.Add(str);

    end; //for each line
    TextEditor.Lines.Assign(tmp);
  finally
    tmp.Free;
  end;
end;

procedure TForm1.UpdateSuggestions;
var
  str: string;
  tmp: TStringList;
  bmap: TBitmap;
  cy: integer = 0;
begin
  try
    bmap := TBitmap.Create;
    tmp := TStringList.Create;
    for str in FAllTags do
      if str.StartsWith(AwesomeBar.Text) then
        tmp.Add(str);

    if tmp.Count = 0 then
      tmp.Assign(FAllTags);

    tmp.Delimiter := #10;
    Suggestions.Text := tmp.DelimitedText;
    bmap.Canvas.Font := Suggestions.Font;
    if Suggestions.Lines.Count <> 0 then
      cy := bmap.Canvas.TextHeight(Suggestions.Lines[0]);

    Suggestions.Height := Suggestions.Lines.Count * cy + cy div 2;
  finally
    tmp.Free;
    bmap.Free;
  end;
end;

procedure TForm1.SaveNotes;
begin
  FAllLines.Assign(FDiscardedLines);
  FAllLines.AddStrings(TextEditor.Lines);
  FAllLines.SaveToFile(ExtractFilePath(Application.ExeName) + 'allnotes.txt');
  CollectAllTags;
  TextEditor.MarkTextAsSaved;
  TextEditor.Modified := False;
end;

function TForm1.QueryUnsavedChanges: TModalResult;
const
  title = 'Unsaved changes';
  message = 'There are unsaved changes. Save them?';
begin
  Result := MessageDlg(title, message, mtConfirmation, mbYesNoCancel, 0);
end;

procedure TForm1.RefreshFoundPoints;
var
  i, spot, x, y: integer;
begin
  SetLength(FFoundTextPoints, 0);
  for i := 0 to TextEditor.Lines.Count do
  begin
    spot := 0;
    while True do
    begin
      spot := PosEx(UpperCase(TextQuery.Text), UpperCase(TextEditor.Lines[i]), spot + 1);
      if spot <> 0 then
      begin
        x := spot + Length(TextQuery.Text);
        y := i + 1;
        SetLength(FFoundTextPoints, Length(FFoundTextPoints) + 1);
        FFoundTextPoints[High(FFoundTextPoints)].SetLocation(x, y);
      end
      else
        Break;
    end; //while true
  end; //for line
end;

procedure TForm1.MoveCursorToNextFind;
var
  pt, c: TPoint;
  i: integer;
begin
  c := TextEditor.CaretXY;
  for i := 0 to High(FFoundTextPoints) do
  begin
    pt := FFoundTextPoints[i];
    if (c.y < pt.y) or ((c.y = pt.y) and (c.x < pt.x)) then
    begin
      TextEditor.CaretXY := pt;
      TextQueryStatusLabel.Caption :=
        Format('Find: %d/%d', [i + 1, Length(FFoundTextPoints)]);
      Exit;
    end; //if
  end; //for

  if Length(FFoundTextPoints) <> 0 then
  begin
    TextEditor.CaretXY := FFoundTextPoints[0];
    TextQueryStatusLabel.Caption := Format('Find: 1/%d', [Length(FFoundTextPoints)]);
  end
  else
    TextQueryStatusLabel.Caption := 'No Results';
end;

end.
