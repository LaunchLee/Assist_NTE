#RequireAdmin
#Region
#AutoIt3Wrapper_UseX64=y
#EndRegion

#include "Libs\autoit-opencv-com\udf\opencv_udf_utils.au3"
#include <GDIPlus.au3>
#include <GUIConstantsEx.au3>
#include <ScreenCapture.au3>
#include <StaticConstants.au3>

; Assume the game window size is 1282x759, not the client area size.
;   The size is it because my template images are captured on this size.
;   ShareX can capture the game window in 1282x759.
; The function `ImageSearch` has a parameter relating to this size.

DllCall("user32.dll", "bool", "SetProcessDPIAware")
Local $arrDPIs = DllCall("user32.dll", "uint", "GetDpiForSystem") ; Windows 10+
Local $iWinScale = $arrDPIs[0] / 96 ; DPI 96 is 100%

_OpenCV_Open("Libs\opencv\build\x64\vc16\bin\opencv_world4120.dll", "Libs\autoit-opencv-com\autoit_opencv_com4120.dll")
_GDIPlus_Startup()
OnAutoItExitRegister("_OnAutoItExit")

Global $sGameWinTitle   = "异环"
Global $sGameResDir     = @ScriptDir & "\Games\NTE\"
Global $sScriptLog      = @ScriptDir & "\Game_NTE.log"
Global $iLoopTimer      = 500

Global $bCafeGameAuto   = True
Global $iCafeGameState  = 0
Global $hCafeGameTimer  = 0

Global $bFishAuto       = True
Global $bFishCatching   = False

Global $bWriteLogOn     = False
Global $bRunning        = False
Global $bPausing        = False
Global $iPausingTimer   = 0
Global $iPausingMax     = $iLoopTimer
Global $bSingleRunning  = False

Global $cv = _OpenCV_get()
If Not IsObj($cv) Then
    MsgBox(16, "Error", "Failed to get OpenCV COM object.")
    Exit
EndIf


; The theme
Global $bIsDark = False
Global $c_Dark_BG       = 0x1F1F1F, $c_Dark_Text      = 0xF0F0F0
Global $c_Light_BG      = 0xF3F3F3, $c_Light_Text     = 0x000000
Global $c_Status_BG     = 0x000000, $c_Status_Text    = 0xFFFFFF
Global $aThemeControls[20], $iCtrlCount = 0

Func _RegisterThemeCtrl($iCtrlID)
    $aThemeControls[$iCtrlCount] = $iCtrlID
    $iCtrlCount += 1
EndFunc

; The font and size.
Local $sFont = "Segoe UI"
Local $iFontSize = 10
Local $iGUIWidth = Int(255 * $iWinScale), $iGUIHeight = Int(255 * $iWinScale)

Local $hGUI = GUICreate("NTE Auto", $iGUIWidth, $iGUIHeight)
GUISetFont($iFontSize, $FW_NORMAL, 0, $sFont)

; [ Normal, Hover, Clicked ] Colors
Global $aBtnColor_Dark[3]  = [0x333333, 0x444444, 0x222222]
Global $aBtnColor_Light[3] = [0xE1E1E1, 0xD0D0D0, 0xB8B8B8]
Global $bBtnHovered = False
Local $iBtnW = Int(100 * $iWinScale), $iBtnH = Int(40 * $iWinScale)
; Local $btnStart = GUICtrlCreateButton("Start", Int(($iGUIWidth - $iBtnW) / 2), Int(10 * $iWinScale), $iBtnW, $iBtnH)
Global $btnStart = GUICtrlCreateLabel("Start", Int(($iGUIWidth - $iBtnW) / 2), Int(10 * $iWinScale), $iBtnW, $iBtnH, BitOR($SS_CENTER, $SS_CENTERIMAGE))
GUICtrlSetFont($btnStart, 11, $FW_BOLD, 0, $sFont)

Local $iPadTop = 3
Local $iStatusW = Int(120 * $iWinScale), $iStatusH = Int(25 * $iWinScale) - $iPadTop
Local $iStatusX = Int(($iGUIWidth - $iStatusW) / 2)
Local $iStatusY = Int(10 * $iWinScale) + $iBtnH + Int(10 * $iWinScale) ; 合并 Gap 运算

Local $lblStatusPad = GUICtrlCreateLabel("", $iStatusX, $iStatusY, $iStatusW, $iPadTop)
GUICtrlSetBkColor($lblStatusPad, 0x000000)
; Initial string length needs attention.
Global $lblStatus = GUICtrlCreateLabel("  Status: Idle    ", $iStatusX, $iStatusY + $iPadTop, $iStatusW, $iStatusH)
GUICtrlSetBkColor($lblStatus, 0x000000)
GUICtrlSetColor($lblStatus, 0xFFFFFF)

Local $iTipsW = Int(235 * $iWinScale), $iTipsH = Int(20 * $iWinScale)
Local $iTipsX = Int(($iGUIWidth - $iTipsW) / 2)
Local $iTipsY = $iStatusY + $iStatusH + Int(10 * $iWinScale)
Local $iTipsGap = $iTipsH + Int(5 * $iWinScale)

Local $aTipsText[3] = [ _
    "Tip1: Press End to stop looping.", _
    "Tip2: Keep an eye on the game.", _
    "Tip3: 1280x720 by game settings." _
]
For $i = 0 To 2
    Local $hIdTip = GUICtrlCreateLabel($aTipsText[$i], $iTipsX, $iTipsY + ($i * $iTipsGap), $iTipsW, $iTipsH)
    _RegisterThemeCtrl($hIdTip)
Next

Local $iChkBoxW = Int(18 * $iWinScale)
Local $iChkBoxP = Int(1 * $iWinScale)

Local $iChkDebugW = Int(100 * $iWinScale), $iChkDebugH = Int(20 * $iWinScale)
Local $iChkDebugY = $iGUIHeight - Int(25 * $iWinScale)
Local $iChkDebugX = Int(($iGUIWidth - $iChkDebugW) / 2)
Local $chkDebug = GUICtrlCreateCheckbox("", $iChkDebugX, $iChkDebugY, $iChkBoxW, $iChkDebugH)
Local $chkDebugText = GUICtrlCreateLabel("Enable log", $iChkDebugX + $iChkBoxW, $iChkDebugY + $iChkBoxP, $iChkDebugW - $iChkBoxW, $iChkDebugH)
_RegisterThemeCtrl($chkDebugText)

Local $iChkCafeW = Int(180 * $iWinScale), $iChkCafeH = Int(20 * $iWinScale)
Local $iChkCafeY = $iChkDebugY - Int(25 * $iWinScale)
Local $iChkCafeX = Int(($iGUIWidth - $iChkCafeW) / 2)
Local $chkCafeGameAuto = GUICtrlCreateCheckbox("", $iChkCafeX, $iChkCafeY, $iChkBoxW, $iChkCafeH)
Local $chkCafeGameAutoText = GUICtrlCreateLabel("Enable CafeGame1-1 Auto", $iChkCafeX + $iChkBoxW, $iChkCafeY + $iChkBoxP, $iChkCafeW - $iChkBoxW, $iChkCafeH)
GUICtrlSetState($chkCafeGameAuto, $GUI_CHECKED)
_RegisterThemeCtrl($chkCafeGameAutoText)

Local $iChkFishW = Int(180 * $iWinScale), $iChkFishH = Int(20 * $iWinScale)
Local $iChkFishY = $iChkCafeY - Int(25 * $iWinScale)
Local $iChkFishX = Int(($iGUIWidth - $iChkFishW) / 2)
Local $chkFishAuto = GUICtrlCreateCheckbox("", $iChkFishX, $iChkFishY, $iChkBoxW, $iChkFishH)
Local $chkFishAutoText = GUICtrlCreateLabel("Enable Fishing Auto", $iChkFishX + $iChkBoxW, $iChkFishY + $iChkBoxP, $iChkFishW - $iChkBoxW, $iChkFishH)
GUICtrlSetState($chkFishAuto, $GUI_CHECKED)
_RegisterThemeCtrl($chkFishAutoText)

; Listen to the theme change
GUIRegisterMsg(0x001A, "WM_SETTINGCHANGE")
_ApplySystemTheme($hGUI)

Func WM_SETTINGCHANGE($hWnd, $iMsg, $wParam, $lParam)
    _ApplySystemTheme($hGUI)
    Return $GUI_RUNDEFMSG
EndFunc

Func _ApplySystemTheme($hWnd)
    Local $iReg = RegRead("HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme")

    If @error Then Return

    Local $bCurrentIsDark = ($iReg == 0)
    $bIsDark = $bCurrentIsDark

    Local $cBkColor = $bIsDark ? $c_Dark_BG : $c_Light_BG
    Local $cTextColor = $bIsDark ? $c_Dark_Text : $c_Light_Text

    GUISetBkColor($cBkColor, $hWnd)

    ; Button theme
    Local $aCurrentBtnSrc = $bIsDark ? $aBtnColor_Dark : $aBtnColor_Light
    GUICtrlSetBkColor($btnStart, $aCurrentBtnSrc[0])
    GUICtrlSetColor($btnStart, $bIsDark ? 0xFFFFFF : 0x000000)

    ; Ctrl theme
    For $i = 0 To $iCtrlCount - 1
        Local $hIdCtrl = $aThemeControls[$i]
        GUICtrlSetColor($hIdCtrl, $cTextColor)
        GUICtrlSetBkColor($hIdCtrl, $cBkColor)
    Next

    Local $pDark = DllStructCreate("int")
    DllStructSetData($pDark, 1, $bIsDark ? 1 : 0)
    DllCall("dwmapi.dll", "long", "DwmSetWindowAttribute", "hwnd", $hWnd, "dword", 20, "ptr", DllStructGetPtr($pDark), "dword", 4)
EndFunc

$iBtnLeft   = -1
$iBtnTop    = -1
$iBtnRight  = -1
$iBtnBottom = -1

; GUI Start
GUISetState(@SW_SHOW)
HotKeySet("{END}", "ActionStop")
While True
    Local $aMousePos = GUIGetCursorInfo($hGUI)
    If Not @error Then
        Local $iMX = $aMousePos[0]
        Local $iMY = $aMousePos[1]
        Local $aColors = $bIsDark ? $aBtnColor_Dark : $aBtnColor_Light

        If $iBtnLeft = -1 Then
            Local $aBtnPos = ControlGetPos($hGUI, "", $btnStart)
            $iBtnLeft   = $aBtnPos[0]
            $iBtnTop    = $aBtnPos[1]
            $iBtnRight  = $aBtnPos[0] + $aBtnPos[2]
            $iBtnBottom = $aBtnPos[1] + $aBtnPos[3]
        EndIf

        If ($iMX >= $iBtnLeft And $iMX <= $iBtnRight) And ($iMY >= $iBtnTop And $iMY <= $iBtnBottom) Then
            If Not $bBtnHovered Then
                $bBtnHovered = True
                GUICtrlSetBkColor($btnStart, $aColors[1])
            EndIf
        Else
            If $bBtnHovered Then
                $bBtnHovered = False
                GUICtrlSetBkColor($btnStart, $aColors[0])
            EndIf
        EndIf
    EndIf

    Switch GUIGetMsg()
        ; When click close button
        Case $GUI_EVENT_CLOSE
            Exit
        Case $btnStart
            Local $aColors = $bIsDark ? $aBtnColor_Dark : $aBtnColor_Light
            GUICtrlSetBkColor($btnStart, $aColors[2])
            Sleep(80)
            GUICtrlSetBkColor($btnStart, $aColors[1])
            If $bRunning Then
                ActionStop()
            Else
                ActionStart()
            EndIf

        ; The check boxes
        Case $chkDebug
            $bWriteLogOn = (GUICtrlRead($chkDebug) = $GUI_CHECKED)

        Case $chkCafeGameAuto
            $bCafeGameAuto = (GUICtrlRead($chkCafeGameAuto) = $GUI_CHECKED)

        Case $chkFishAuto
            $bFishAuto = (GUICtrlRead($chkFishAuto) = $GUI_CHECKED)
    EndSwitch
WEnd

; Functions
Func ResetPausingState()
    $bPausing = False
    $iPausingTimer = 0
    $iPausingMax = 0
EndFunc

Func ActionStart()
    GUICtrlSetData($btnStart, "Stop")
    GUICtrlSetData($lblStatus, "  Status: Running ")
    GUICtrlSetColor($lblStatus, 0x00FF00)
    $bRunning = True
    AdlibRegister("AutoClick", $iLoopTimer)
EndFunc

Func ActionStop()
    GUICtrlSetData($btnStart, "Start")
    GUICtrlSetData($lblStatus, "  Status: Idle    ")
    GUICtrlSetColor($lblStatus, 0xFFFFFF)
    $bRunning = False
    ResetPausingState()
    AdlibUnRegister("AutoClick")
EndFunc

Func ActionContinue()
    If Not $bRunning Then Return
    GUICtrlSetData($lblStatus, "  Status: Running ")
    GUICtrlSetColor($lblStatus, 0x00FF00)
    ResetPausingState()
EndFunc

Func ActionPause($iMilliSeconds)
    GUICtrlSetData($lblStatus, "  Status: Waiting ")
    GUICtrlSetColor($lblStatus, 0xFFD966)
    $iPausingTimer = 0
    $iPausingMax = $iMilliSeconds
    $bPausing = True
EndFunc

Func _WinAPI_GetPosWithoutShadow($hWnd)
    If Not IsHWnd($hWnd) Then $hWnd = WinGetHandle($hWnd)
    If Not $hWnd Then Return False

    Local $aPos[4]
    Local $bSuccess = False

    Local $tRect = DllStructCreate("long Left;long Top;long Right;long Bottom;")
    ; DWMWA_EXTENDED_FRAME_BOUNDS = 9
    Local $aRet = DllCall("dwmapi.dll", "long", "DwmGetWindowAttribute", _
            "hwnd", $hWnd, _
            "dword", 9, _
            "ptr", DllStructGetPtr($tRect), _
            "dword", DllStructGetSize($tRect))

    If Not @error And $aRet[0] = 0 Then
        $aPos[0] = DllStructGetData($tRect, "Left")
        $aPos[1] = DllStructGetData($tRect, "Top")
        $aPos[2] = DllStructGetData($tRect, "Right") - $aPos[0]  ; Width
        $aPos[3] = DllStructGetData($tRect, "Bottom") - $aPos[1] ; Height
        $bSuccess = True
    EndIf

    If Not $bSuccess Then
        Local $aNativePos = WinGetPos($hWnd)
        If IsArray($aNativePos) Then
            $aPos = $aNativePos
            $bSuccess = True
        EndIf
    EndIf

    If Not $bSuccess Then Return False

    Return $aPos
EndFunc

; Image Search Functions.
; #FUNCTION# ==========================================================================================================
; Name ..........: ImageSearch
; Description ...: Find image in the game window or subarea relative to the game window.
; Syntax ........: ImageSearch($sImageFile[, $fThreshold = Default[, $arrSubArea = Default[, $iBaseHeight = Default]]])
; Parameters ....: $sImageFile      - Image path.
;                  $fThreshold      - [optional] The threshold. Default is 0.8
;                  $arrSubArea      - [optional] The sub area [x, y, w, h] relative to the game window. Default is the
;                                                whole game window.
;                  $iBaseHeight     - [optional] The base game window height where you capture the template images. So
;                                                the  captured images should be capture in the same window size. If the
;                                                running game window size is different, the template image will be
;                                                resized proportionally to  match the window size. Though it's better
;                                                to keep your game window size consistent.
; Return values .: Array of area relative to the game window if find or subarea if provided. Otherwise just silent.
; Remarks .......:
;   Assuming using SmartSystemMenu to resize to 1280x720 that give the game window size 1282x759 reducing the border
;   shadow size I think.
; =====================================================================================================================
Func ImageSearch($sImageFile, $fThreshold = Default, $arrSubArea = Default, $iBaseHeight = Default, $iMatchMethod = Default)
    If $fThreshold = Default Then $fThreshold = 0.80
    If $iBaseHeight = Default Then $iBaseHeight = 759

    Local $imgTempl = _OpenCV_imread_and_check($sImageFile)

    Local $arrArea = _WinAPI_GetPosWithoutShadow($sGameWinTitle)
    Local $iActualHeight = $arrArea[3]
    If $arrSubArea <> Default Then
        $arrArea[0] += $arrSubArea[0]
        $arrArea[1] += $arrSubArea[1]
        $arrArea[2] = $arrSubArea[2]
        $arrArea[3] = $arrSubArea[3]
    EndIf
    Local $imgScreen = _OpenCV_GetDesktopScreenMat($arrArea)

    If $imgTempl.empty() Or $imgScreen.empty() Then
        Return False
    EndIf

    If $iActualHeight <> $iBaseHeight Then
        Local $fProportion = $iActualHeight / $iBaseHeight
        If $arrSubArea <> Default Then
            $arrArea[0] += int($arrSubArea[0] * ($fProportion - 1))
            $arrArea[1] += int($arrSubArea[1] * ($fProportion - 1))
        EndIf
        $arrArea[2] = int($arrArea[2] * $fProportion)
        $arrArea[3] = int($arrArea[3] * $fProportion)
        Local $iAdjWidth = int($imgTempl.width * $fProportion)
        Local $iAdjHeight = int($imgTempl.height * $fProportion)
        $imgTempl = $cv.resize($imgTempl, _OpenCV_Size($iAdjWidth, $iAdjHeight))
    EndIf

    Local $iN = 1

    Local $imgTemplOpt = $cv.cvtColor($imgTempl, $CV_COLOR_BGR2GRAY)
    Local $imgScreenOpt = $cv.cvtColor($imgScreen, $CV_COLOR_BGR2GRAY)
    Local $iTotalCosts = $imgScreen.width * $imgScreen.height * $imgTempl.width * $imgTempl.height
    If $iTotalCosts > 147456000000 Then
        $iN = 2
        $imgTemplOpt = $cv.resize($imgTemplOpt, _OpenCV_Size($imgTempl.width / $iN, $imgTempl.height / $iN))
        $imgScreenOpt = $cv.resize($imgScreenOpt, _OpenCV_Size($imgScreen.width / $iN, $imgScreen.height / $iN))
    EndIf
    Local $matchResults = _OpenCV_FindTemplate($imgScreenOpt, $imgTemplOpt, $fThreshold, $iMatchMethod)  ; Covariant Matrix Normal
    If IsArray($matchResults) And UBound($matchResults) > 0 Then
        Local $arrRect = [$matchResults[0][0] * $iN, $matchResults[0][1] * $iN, $imgTempl.width, $imgTempl.height]
        Return SetError(0, 0, $arrRect)
    Else
        Return SetError(0, 0, False)
    EndIf
EndFunc

; $arrArea is the window area. $arrRect is the subarea relative to the window area.
; When no shifts, default to click the center of the image($subRect). The shifts are relative to the center.
Func ClickRelateWindow($arrArea, $arrRect, $iShiftX = 0, $iShiftY = 0, $bBgClick = False)
    Local $iCenterX = $arrRect[0] + Int($arrRect[2] / 2) + $iShiftX
    Local $iCenterY = $arrRect[1] + Int($arrRect[3] / 2) + $iShiftY
    If $bBgClick Then
        ; Only when this message is accepted, but mostly can't because it's cheat apparently.
        ControlClick($sGameWinTitle, "", "", "left", 1, $iCenterX, $iCenterY)
    Else
        MouseClick("left", $arrArea[0] + $iCenterX, $arrArea[1] + $iCenterY, 1, 0)
    EndIf
EndFunc

; CD: If the image would still be presented for a while after being clicked,
; then if in the next loop the same image is the
; "next" detected, skip it for 1 as the CD unit.
Func ClickImage($sImageFile, $fThreshold = 0.85, $iShiftX = 0, $iShiftY = 0, $bCDOn = False, $iCDMax = 2, $arrSubArea = Default, $iBaseHeight = 759)
    Static $sCDImageFile = ""
    Static $iCD = 0

    Local $arrRect = ImageSearch($sImageFile, $fThreshold, $arrSubArea, $iBaseHeight)
    If Not IsArray($arrRect) Then
        Return SetError(1, 0, False)
    EndIf

    If $bCDOn And $sCDImageFile = $sImageFile Then
        $iCD += 1
        If $iCD < $iCDMax Then
            Return SetError(0, 0, True)
        Endif
        $iCD = 0
    Else
        $iCD = 0
        $sCDImageFile = $sImageFile
    EndIf

    Local $arrArea = _WinAPI_GetPosWithoutShadow($sGameWinTitle)
    Local $iActualHeight = $arrArea[3]
    If $arrSubArea <> Default Then
        $arrRect[0] += $arrSubArea[0]
        $arrRect[1] += $arrSubArea[1]
    EndIf

    If $iActualHeight <> $iBaseHeight And $arrSubArea <> Default Then
        Local $fProportion = $iActualHeight / $iBaseHeight
        $arrRect[0] += int($arrSubArea[0] * ($fProportion - 1))
        $arrRect[1] += int($arrSubArea[1] * ($fProportion - 1))
    EndIf

    ClickRelateWindow($arrArea, $arrRect, $iShiftX, $iShiftY)
    Return SetError(0, 0, True)
EndFunc

; Log Function
Func WriteLog($msg)
    Local $hFile = FileOpen($sScriptLog, $FO_APPEND + $FO_CREATEPATH)
    If $hFile = -1 Then Return SetError(1, 0, 0)

    FileWriteLine($hFile, StringFormat("%04d-%02d-%02d %02d:%02d:%02d - %s", @YEAR, @MON, @MDAY, @HOUR, @MIN, @SEC, $msg))
    FileClose($hFile)
EndFunc

; Autoclick Function Group
Func FarmCPByCafeGame()
    Local $fLow = 0.55, $fDefault = 0.60, $fHigh = 0.90
    Local $bCD = False, $iCDFactor = 2

    Local $arrCafeGameLast = [14, 640, 200, 55]
    Local $arrCafeGame0101 = [14, 260, 200, 55]
    Local $arrCafeGameStart = [1059, 681, 175, 55]
    If IsArray(ImageSearch($sGameResDir & "CafeGame_Last.png", $fDefault, $arrCafeGameLast)) Then
        Local $arrArea = _WinAPI_GetPosWithoutShadow($sGameWinTitle)
        If @error Then Return

        Local $iTargetX = $arrArea[0] + Int($arrArea[2] * 0.1)
        Local $iTargetY = $arrArea[1] + Int($arrArea[3] * 0.5)
        MouseMove($iTargetX, $iTargetY, 0)
        MouseWheel("up", 100)
    EndIf
    If ClickImage($sGameResDir & "CafeGame_1-1.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrCafeGame0101) Then
        If ClickImage($sGameResDir & "CafeGame_Start.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrCafeGameStart) Then
            $iCafeGameState = 1
        EndIf
    EndIf

    If Not $bRunning Then Return

    Local $Endless = 0
    Local $arrOnReadyGo = [579, 53, 130, 29]
    Local $arrOnLBaseA = [0, 658, 167, 101]
    Local $arrOnLBaseB = [407, 658, 167, 101]
    Local $arrOnLCut = [176, 653, 229, 106]
    Local $arrOnLPut = [184, 523, 150, 106]
    Local $arrOnLHoldA = [0, 530, 194, 94]
    Local $arrOnLHoldB = [332, 530, 194, 94]
    Local $arrOnLDishB = [128, 470, 70, 60]
    Local $arrOnLDishC = [242, 470, 70, 60]
    Local $arrOnMBase = [577, 658, 167, 101]
    Local $arrOnMBake = [761, 658, 175, 101]
    Local $arrOnMPut = [547, 531, 190, 91]
    Local $arrOnMDishC = [687, 463, 61, 50]
    Local $arrOnTitle = [1073, 64, 126, 28]
    Local $arrOnExit = [4, 40, 55, 56]
    While $iCafeGameState > 0 And $Endless <= 10
        If IsArray(ImageSearch($sGameResDir & "CafeGame_1-1\OnTitle.png", $fDefault, $arrOnTitle)) And $iCafeGameState > 0 Then
            If $iCafeGameState = 1 And IsArray(ImageSearch($sGameResDir & "CafeGame_1-1\OnReadyGo.png", $fDefault, $arrOnReadyGo)) Then
                If ClickImage($sGameResDir & "CafeGame_1-1\OnLBaseA.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrOnLBaseA) Then
                    $iCafeGameState += 1
                    $hCafeGameTimer = TimerInit()
                EndIf
            EndIf
            If $iCafeGameState = 2 And ClickImage($sGameResDir & "CafeGame_1-1\OnMBase.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrOnMBase) Then
                $iCafeGameState += 1
            EndIf
            If $iCafeGameState = 3 And TimerDiff($hCafeGameTimer) > 3000 Then
                If ClickImage($sGameResDir & "CafeGame_1-1\OnLBaseB.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrOnLBaseB) Then
                    $iCafeGameState += 1
                    $hCafeGameTimer = TimerInit()
                EndIf
            EndIf
            If $iCafeGameState = 4 And TimerDiff($hCafeGameTimer) > 3000 Then
                If ClickImage($sGameResDir & "CafeGame_1-1\OnLHoldBS1A.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrOnLHoldB) Then
                    $iCafeGameState += 1
                    $hCafeGameTimer = TimerInit()
                EndIf
            EndIf
            If $iCafeGameState = 5 And ClickImage($sGameResDir & "CafeGame_1-1\OnMBakeS1A.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrOnMBake) Then
                $iCafeGameState += 1
            EndIf
            If $iCafeGameState = 6 And TimerDiff($hCafeGameTimer) > 1000 Then
                If ClickImage($sGameResDir & "CafeGame_1-1\OnLDishC.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrOnLDishC) Then
                    $iCafeGameState += 1
                    $hCafeGameTimer = TimerInit()
                EndIf
            EndIf
            If $iCafeGameState = 7 And TimerDiff($hCafeGameTimer) > 2000 Then
                If ClickImage($sGameResDir & "CafeGame_1-1\OnMDishC.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrOnMDishC) Then
                    $iCafeGameState += 1
                    $hCafeGameTimer = TimerInit()
                EndIf
            EndIf
            If $iCafeGameState = 8 And TimerDiff($hCafeGameTimer) > 5000 Then
                If ClickImage($sGameResDir & "CafeGame_1-1\OnLHoldAS1A.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrOnLHoldA) Then
                    $iCafeGameState += 1
                    $hCafeGameTimer = TimerInit()
                EndIf
            EndIf
            If $iCafeGameState = 9 And TimerDiff($hCafeGameTimer) > 1000 Then
                If ClickImage($sGameResDir & "CafeGame_1-1\OnLDishB.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrOnLDishB) Then
                    $iCafeGameState += 1
                    $hCafeGameTimer = TimerInit()
                EndIf
            EndIf
            If $iCafeGameState = 10 And TimerDiff($hCafeGameTimer) > 500 Then
                If ClickImage($sGameResDir & "CafeGame_1-1\OnExit.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrOnExit) Then
                    $iCafeGameState = 0
                EndIf
            EndIf
        Else
            $Endless += 1
        EndIf

        If Not $bRunning Then Return
    WEnd

    Local $arrCafeGameFail = [537, 146, 214, 76]
    Local $arrCafeGameFailExit = [462, 574, 92, 46]
    Local $arrCafeGameWinGet = [737, 576, 75, 40]
    Local $arrCafeGameNoGains = [711, 613, 137, 43]
    If IsArray(ImageSearch($sGameResDir & "CafeGame_Fail.png", $fDefault, $arrCafeGameFail)) Then
        ClickImage($sGameResDir & "CafeGame_FailExit.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrCafeGameFailExit)
    EndIf
    If IsArray(ImageSearch($sGameResDir & "CafeGame_Win.png", $fDefault, $arrCafeGameFail)) Then
        If IsArray(ImageSearch($sGameResDir & "CafeGame_NoGains.png", $fHigh, $arrCafeGameNoGains)) Then
            ActionStop()
            GUICtrlSetData($lblStatus, "  Cafe: Limited   ")
            Return
        EndIf
        ClickImage($sGameResDir & "CafeGame_WinGet.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrCafeGameWinGet)
    EndIf
EndFunc

Func Fishing($iBaseHeight = 759)
    Local $fLow = 0.40, $fDefault = 0.60, $fHigh = 0.80
    Local $bCD = False, $iCDFactor = 2
    Local $iReactionTime = 200 ; ms

    Local $arrFishStart = [1016, 644, 126, 46]
    Local $arrFishReady = [915, 670, 45, 45]
    Local $arrFishToss = [1161, 656, 48, 56]
    Local $arrFishCatch = [500, 185, 300, 55]
    Local $arrFishCatch2 = [1165, 702, 44, 21]
    Local $arrFishDone = [557, 671, 169, 40]
    Local $arrFishFail = [570, 368, 137, 57]
    Local $arrFishNoBaits = [504, 362, 280, 73]
    Local $arrFishFull = [440, 372, 400, 55]

    Local $arrArea = _WinAPI_GetPosWithoutShadow($sGameWinTitle)

    Local $iAreaCenterX = $arrArea[0] + ($arrArea[2] * 0.50)
    Local $iAreaCenterY = $arrArea[1] + ($arrArea[3] * 0.60)

    Local $iActualHeight = $arrArea[3]
    Local $fProportion = $iActualHeight / $iBaseHeight

    Local $arrFishBar = [int(406 * $fProportion), int(88 * $fProportion), int(475 * $fProportion), 1]
    Local $fBarISpeed = 0.4 * $fProportion ; pixels / ms
    Local $iBarICenter = 0, $iBarIDiff = 0, $iBarISafeDiff = 0, $iBarIMoveMs = 0

    Local $iLineColor = 0x9DFEF6, $iLineTolerance = 20
    Local $iEndless = 0

    Local $arrBarArea = [$arrArea[0] + $arrFishBar[0], $arrArea[1] + $arrFishBar[1], $arrFishBar[2], $arrFishBar[3]]

    While $bFishCatching
        Local $imgScreen = _OpenCV_GetDesktopScreenMat($arrBarArea)
        If $imgScreen.empty() Then Return
        ; $cv.imwrite("FishingBar.png", $imgScreen)

        Local $imgScreenHSV = $cv.cvtColor($imgScreen, $CV_COLOR_BGR2HSV)

        Local $maskGreen = _OpenCV_ObjCreate("cv.Mat")
        Local $cvGreenMin = [79, 171, 191]
        Local $cvGreenMax = [87, 221, 241]
        $cv.inRange($imgScreenHSV, $cvGreenMin, $cvGreenMax, $maskGreen)

        Local $maskLine = _OpenCV_ObjCreate("cv.Mat")
        Local $cvLineMin = [23, 72, 230]
        Local $cvLineMax = [31, 122, 255]
        $cv.inRange($imgScreenHSV, $cvLineMin, $cvLineMax, $maskLine)

        Local $iBarLeft = -1, $iBarRight = -1, $iBarI = -1
        Local $iGreenCount = 0, $iGreenRecA = 0
        Local $iLineCount = 0
        For $i = 0 To $arrFishBar[2] - 1
            If $maskGreen.at(0, $i) = 255 Then
                If $iGreenCount = 0 Then $iGreenRecA = $i
                $iGreenCount += 1
                If $iGreenCount > 5 Then
                    If $iBarLeft = -1 Then $iBarLeft = $iGreenRecA
                    $iBarRight = $i
                EndIf
            Else
                $iGreenCount = 0
            EndIf

            If $maskLine.at(0, $i) = 255 Then
                $iLineCount += 1
                If $iLineCount > 1 Then $iBarI = $i
            Else
                $iLineCount = 0
            EndIf
        Next

        ; GUICtrlSetData($lblStatus, " L:" & $iBarLeft & " R:" & $iBarRight & " I:" & $iBarI)
        If $iBarLeft > 0 And $iBarRight > 0 And $iBarI > 0 Then
            $iEndless = 0
            $iBarISafeDiff = int(($iBarRight - $iBarLeft) * 0.2)
            $iBarICenter = int(($iBarRight + $iBarLeft) / 2)
            $iBarIDiff = $iBarI - $iBarICenter
            If Abs($iBarIDiff) > $iBarISafeDiff Then
                $iBarIMoveMs = int(Abs($iBarIDiff) / $fBarISpeed)
                If $iBarIDiff > 0 Then
                    Send("{d up}")
                    Send("{a down}")
                Else
                    Send("{a up}")
                    Send("{d down}")
                EndIF
            Else
                Send("{a up}")
                Send("{d up}")
            EndIf
        Else
            $iEndless += 1
        EndIf
        If ClickImage($sGameResDir & "Fish_Done.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrFishDone) Or _
           IsArray(ImageSearch($sGameResDir & "Fish_Fail.png", $fDefault, $arrFishFail)) Or _
           Not $bRunning Or $iEndless > 10 Then
            Send("{a up}")
            Send("{d up}")
            $bFishCatching = False
            ; GUICtrlSetData($lblStatus, "  Status: Running ")
        EndIf
        If IsArray(ImageSearch($sGameResDir & "Fish_NoBaits.png", $fDefault, $arrFishNoBaits)) Then
            ActionStop()
            GUICtrlSetData($lblStatus, "    Fish: NoBaits ")
            Return
        EndIf
        If IsArray(ImageSearch($sGameResDir & "Fish_Full.png", $fDefault, $arrFishFull)) Then
            ActionStop()
            GUICtrlSetData($lblStatus, "    Fish: Full    ")
            Return
        EndIf
    WEnd

    ClickImage($sGameResDir & "Fish_Start.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrFishStart)
    If IsArray(ImageSearch($sGameResDir & "Fish_Ready.png", $fDefault, $arrFishReady)) Then
        Sleep($iReactionTime)
        ClickImage($sGameResDir & "Fish_Toss.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrFishToss)
        MouseMove($iAreaCenterX, $iAreaCenterY, 0)
    EndIf
    If Not $bRunning Then Return
    If IsArray(ImageSearch($sGameResDir & "Fish_Catch.png", $fDefault, $arrFishCatch)) Or _
       IsArray(ImageSearch($sGameResDir & "Fish_Catch2.png", $fHigh, $arrFishCatch2, Default, $CV_TM_SQDIFF_NORMED)) Or _
       IsArray(ImageSearch($sGameResDir & "Fish_Catch3.png", $fHigh, $arrFishCatch2, Default, $CV_TM_SQDIFF_NORMED)) Then
        Sleep($iReactionTime)
        ClickImage($sGameResDir & "Fish_Toss.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrFishToss)
        MouseMove($iAreaCenterX, $iAreaCenterY, 0)
        $bFishCatching = True
    EndIf
    If Not $bRunning Then Return
    If ClickImage($sGameResDir & "Fish_Done.png", $fDefault, 0, 0, $bCD, $iCDFactor, $arrFishDone) Then
        $bFishCatching = False
    EndIf
    If IsArray(ImageSearch($sGameResDir & "Fish_NoBaits.png", $fDefault, $arrFishNoBaits)) Then
        ActionStop()
        GUICtrlSetData($lblStatus, "    Fish: NoBaits ")
        Return
    EndIf
    If IsArray(ImageSearch($sGameResDir & "Fish_Full.png", $fDefault, $arrFishFull)) Then
        ActionStop()
        GUICtrlSetData($lblStatus, "    Fish: Full    ")
        Return
    EndIf
EndFunc

; Looped Function
Func AutoClick()
    If Not $bRunning Or $bSingleRunning Then Return

    If $bPausing Then
        $iPausingTimer += $iLoopTimer
        If $iPausingTimer >= $iPausingMax Then
            ActionContinue()
        EndIf
        Return
    EndIf

    If Not WinExists($sGameWinTitle) Then
        MsgBox(16, "Error", "Game window not found.")
        ActionStop()
        Return
    EndIf

    Local $hTimer = $bWriteLogOn ? TimerInit() : 0
    WinActivate($sGameWinTitle)

    Local $fLow = 0.55, $fDefault = 0.60, $fHigh = 0.65
    Local $bCD = False, $iCDFactor = 2

    If $bCafeGameAuto Then
        ; CP: City Power
        FarmCPByCafeGame()
    EndIf

    If $bFishAuto Then
        Fishing()
    EndIf

    ClickImage($sGameResDir & "Act_Petting.png", $fDefault, 0, 0, True, $iCDFactor)

    If $bWriteLogOn Then
        WriteLog("AutoClick: " & TimerDiff($hTimer) & " ms")
    EndIf
EndFunc

; Internal Handling
Func _OnAutoItExit()
    _GDIPlus_Shutdown()
    _OpenCV_Close()
EndFunc
