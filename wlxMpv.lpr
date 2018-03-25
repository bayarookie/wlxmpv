{
   WlxMplayer
   -------------------------------------------------------------------------
   This is WLX (Lister) plugin for Double Commander.

   Copyright (C) 2008  Dmitry Kolomiets (B4rr4cuda@rambler.ru)
   Class TExProcess used in plugin was written by Anton Rjeshevsky.
   Gtk2 and Qt support were added by Koblov Alexander (Alexx2000@mail.ru)

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
}

library wlxMPV;

{$mode objfpc}{$H+}
{$include calling.inc}

{$IF NOT (DEFINED(LCLGTK) or DEFINED(LCLGTK2) or DEFINED(LCLQT) or DEFINED(LCLQT5))}
{$DEFINE LCLGTK2}
{$ENDIF}

uses
  {$IFDEF UNIX}
  cthreads,
  {$IFNDEF HEAPTRC}
  cmem,
  {$ENDIF}
  {$ENDIF}
  Classes,
  sysutils, strutils, dl,
  x,
  {$IFDEF LCLGTK} gtk, gdk, glib, {$ENDIF}
  {$IFDEF LCLGTK2} gtk2, gdk2, glib2, gdk2x, {$ENDIF}
  {$IFDEF LCLQT} qt4, {$ENDIF}
  {$IFDEF LCLQT5} qt5, {$ENDIF}
  process,
  math,
  WLXPlugin, IniFiles;
  

var
  wlxmpvIni: string;
  wlxmpvAudio: string = '.mp3;.flac;.ape;.wav;.wv;.wma;.m4a;.aac;.ac3;.ogg;.aiff;.alac;.amr;.opus';
  wlxmpvOSD: string = '${media-title}\n${time-pos} / ${duration} (${percent-pos}%)\n${audio-bitrate}\n${audio-codec}\nsamplerate=${audio-params/samplerate}\nchannels=${audio-params/channel-count}\nformat=${audio-params/format}';

type

//Class implementing mpv control
{ TMPVthread }

TMPVthread=class(TThread)
  public
    hWidget:THandle;	//the integrable widget
    fileName:string;    //filename
    xid:TWindow;	//X window handle
    p:TProcess;         //mpv's process
    pmplayer:string;    //path to mpv
    constructor Create(APlayerPath, AFilename: String);
    destructor Destroy; override;
    procedure SetParentWidget(AWidget:thandle);
  protected
    procedure Execute; override;
  private

  end;

{ TMPVthread }

constructor TMPVthread.Create(APlayerPath, AFilename: String);
begin
  inherited Create(True);
  filename:= AFilename;
  pmplayer:= APlayerPath;
  WriteLn('wlxMpv: found mpv in - ' + pmplayer);
end;

destructor TMPVthread.Destroy;
begin
  while p.Running do
    p.Terminate(0);
  p.Free;
{$IF DEFINED(LCLQT) or DEFINED(LCLQT5)}
  QWidget_Destroy(QWidgetH(hWidget));
{$ELSE}
  gtk_widget_destroy(PGtkWidget(hWidget));
{$ENDIF}
  inherited Destroy;
end;

procedure TMPVthread.SetParentWidget(AWidget: THandle);
{$IF DEFINED(LCLQT) or DEFINED(LCLQT5)}
begin
  hWidget:= THandle(QWidget_create(QWidgetH(AWidget)));
  QWidget_show(QWidgetH(hWidget));
  xid:= QWidget_winId(QWidgetH(hWidget));
end;
{$ELSE}
var
  widget,
  mySocket: PGtkWidget;	//the socket
begin
  widget := PGtkWidget(AWidget);
  mySocket := gtk_socket_new;

  gtk_container_add(GTK_CONTAINER(widget), mySocket);

  gtk_widget_show(mySocket);
  gtk_widget_show(widget);

  gtk_widget_realize(mySocket);

{$IFDEF LCLGTK}
  xid:= (PGdkWindowPrivate(mySocket^.window))^.xwindow;
{$ENDIF}
{$IFDEF LCLGTK2}
  xid:= GDK_WINDOW_XID(mySocket^.window);
{$ENDIF}
  hWidget:= THandle(mySocket);
end;
{$ENDIF}

procedure TMPVthread.Execute;
begin
  p:= TProcess.Create(nil);
  p.Executable:= pmplayer;
  p.Parameters.Add(fileName);
  p.Parameters.Add('--wid=' + IntToStr(xid));
  p.Parameters.Add('--force-window=yes');
  p.Parameters.Add('--keep-open=always');
  p.Parameters.Add('--cursor-autohide-fs-only');
  p.Parameters.Add('--script-opts=osc-visibility=always');
  if Pos(LowerCase(ExtractFileExt(fileName)), wlxmpvAudio)>0 then
  begin
    p.Parameters.Add('--osd-level=3');
    p.Parameters.Add('--osd-status-msg=' + wlxmpvOSD);
  end;
  WriteLn(p.Executable + ' ' + ReplaceText(p.Parameters.CommaText,',',' '));
  p.Execute;
end;


//Custom class contains info for plugin windows
type

{ TPlugInfo }

TPlugInfo = class
  private
    fControls:TStringList;
  public
    fFileToLoad:string;
    fShowFlags:integer;
    //etc
    constructor Create;
    destructor Destroy; override;
    function AddControl(AItem: TMPVthread):integer;
  end;

{ TPlugInfo }

constructor TPlugInfo.Create;
begin
  fControls:=TStringlist.Create;
end;

destructor TPlugInfo.Destroy;
begin
  while fControls.Count>0 do
  begin
    TMPVthread(fControls.Objects[0]).Free;
    fControls.Delete(0);
  end;
  inherited Destroy;
end;

function TPlugInfo.AddControl(AItem: TMPVthread): integer;
begin
  Result := fControls.AddObject(inttostr(PtrUInt(AItem)),TObject(AItem));
end;

{Plugin main part}
var List:TStringList;

function ListLoad(ParentWin: THandle; FileToLoad: PChar; ShowFlags: Integer): THandle; dcpcall;
var
  sPlayerPath: String;
  t: TMPVthread;
  sl: TStringList;
begin
  sl:= TStringList.Create;
  if RunCommand('which', ['mpv'], sPlayerPath) then
  begin
    sl.Text:= sPlayerPath;
    if (sl.Count<>0) then
      sPlayerPath:= sl[0]
    else
      WriteLn('wlxMpv: mpv not found!');
  end;
  sl.Free;
  if sPlayerPath = EmptyStr then Exit(wlxInvalidHandle);

  t:= TMPVthread.Create(sPlayerPath, string(FileToLoad));
  t.SetParentWidget(ParentWin);
  Result:= t.hWidget;

  // Create list if none
  if not Assigned(List) then
    List:= TStringList.Create;

  // Add to list new plugin window and it's info
  List.AddObject(IntToStr(PtrInt(t.hWidget)), TPlugInfo.Create);
  with TPlugInfo(List.Objects[List.Count-1]) do
  begin
    fFileToLoad:= FileToLoad;
    fShowFlags:= ShowFlags;
    AddControl(t);
  end;

  t.Start;
end;

procedure ListCloseWindow(ListWin:thandle); dcpcall;
 var Index:integer; s:string;
begin
  if assigned(List) then
  begin
    writeln('ListCloseWindow quit, List Item count: '+inttostr(List.Count));
    s:=IntToStr(ListWin);
    Index:=List.IndexOf(s);
    if Index>-1 then
    begin
      TPlugInfo(List.Objects[Index]).Free;
      List.Delete(Index);
      writeln('List item n: '+inttostr(Index)+' Deleted');
    end;

    //Free list if it has zero items
    If List.Count=0 then  FreeAndNil(List);
  end;
end;

procedure ListGetDetectString(DetectString:pchar;maxlen:integer); dcpcall;
begin
  StrLCopy(DetectString, '(EXT="AVI")|(EXT="MKV")|(EXT="FLV")|(EXT="MPG")|(EXT="MPEG")|(EXT="MP4")|(EXT="VOB")|(EXT="WEBM")|(EXT="WMV")|(EXT="MOV")|(EXT="3GP")|(EXT="BIK")|(EXT="MP3")|(EXT="FLAC")|(EXT="APE")|(EXT="ALAC")|(EXT="OGG")|(EXT="WMA")|(EXT="WAV")|(EXT="M4A")|(EXT="AAC")|(EXT="AC3")|(EXT="AIFF")|(EXT="VOC")|(EXT="ROQ")|(EXT="AMR")|(EXT="OPUS"))', maxlen);
end;

procedure ListSetDefaultParams(dps:pListDefaultParamStruct); dcpcall;
var
  Ini: TIniFile;
begin
  wlxmpvIni := string(dps^.DefaultIniName);
  writeln('path to ini: ', wlxmpvIni);  //path to ini: ~/.config/doublecmd/wlx.ini or %commander_path%/wlx.ini
  Ini:= TIniFile.Create(wlxmpvIni);
  try
    wlxmpvAudio := Ini.ReadString('wlxMpv', 'Audio', wlxmpvAudio);
    wlxmpvOSD := Ini.ReadString('wlxMpv', 'OSD', wlxmpvOSD);
  finally
    Ini.Free;
  end;
end;

exports
  ListLoad,
  ListCloseWindow,
  ListGetDetectString,
  ListSetDefaultParams;

{$R *.res}

begin
end.

