-- | The default game key-command mapping to be used for UI. Can be overridden
-- via macros in the config file.
module Client.UI.Content.Input
  ( standardKeysAndMouse
#ifdef EXPOSE_INTERNAL
    -- * Internal operations
  , closeDoorTriggers, applyTs
#endif
  ) where

import Prelude ()

import Game.LambdaHack.Core.Prelude

import           Game.LambdaHack.Client.UI.Content.Input
import           Game.LambdaHack.Client.UI.HumanCmd
import qualified Game.LambdaHack.Content.TileKind as TK
import           Game.LambdaHack.Definition.Defs

-- | Description of default key-command bindings.
--
-- In addition to these commands, mouse and keys have a standard meaning
-- when navigating various menus.
standardKeysAndMouse :: InputContentRaw
standardKeysAndMouse = InputContentRaw $ map evalKeyDef $
  -- All commands are defined here, except some movement and leader picking
  -- commands. All commands are shown on help screens except debug commands
  -- and macros with empty descriptions.
  -- The order below determines the order on the help screens.
  -- Remember to put commands that show information (e.g., enter aiming
  -- mode) first.

  -- Main menu
  [ ("e", ([CmdMainMenu], "enter challenges menu>", ChallengesMenu))
  , ("s", ([CmdMainMenu], "start new game", GameRestart))
  , ("x", ([CmdMainMenu], "save and exit to desktop", GameExit))
  , ("v", ([CmdMainMenu], "visit settings menu>", SettingsMenu))
  , ("a", ([CmdMainMenu], "toggle autoplay (insert coin)", Automate))
  , ("?", ([CmdMainMenu], "see command help", Help))
  , ("F12", ([CmdMainMenu], "switch to dashboard", Dashboard))
  , ("Escape", ([CmdMainMenu], "back to playing", AutomateBack))

  -- Minimal command set, in the desired presentation order.
  -- A lot of these are not necessary, but may be familiar to new players.
  , ("E", ( [CmdMinimal, CmdItem, CmdDashboard]
          , "manage equipment of the leader"
          , ChooseItemMenu (MStore CEqp) ))
  , ("g", addCmdCategory CmdMinimal $ grabItems "grab item(s)")
  , ("Escape", ( [CmdMinimal, CmdAim]
               , "open main menu/finish aiming"
               , ByAimMode AimModeCmd { exploration =
                                          ExecuteIfClear MainMenuAutoOff
                                      , aiming = Cancel } ))
  , ("C-Escape", ([CmdNoHelp], "", MainMenuAutoOn))
      -- required by frontends; not shown
  , ("Return", ( [CmdMinimal, CmdAim]
               , "open dashboard/accept target"
               , ByAimMode AimModeCmd { exploration = ExecuteIfClear Dashboard
                                      , aiming = Accept } ))
  , ("space", ( [CmdMinimal, CmdMeta]
              , "clear messages and show history"
              , ExecuteIfClear LastHistory ))
  , ("Tab", ( [CmdMove]
            , "cycle among party members on the level"
            , MemberCycle ))
      -- listed here to keep proper order
  , ("BackTab", ( [CmdMinimal, CmdMove]
              , "cycle among all party members"
              , MemberBack ))
  , ("KP_Multiply", ( [CmdMinimal, CmdAim]
                    , "cycle x-hair among enemies"
                    , AimEnemy ))
  , ("KP_Divide", ([CmdMinimal, CmdAim], "cycle x-hair among items", AimItem))
  , ("c", ( [CmdMinimal, CmdMove]
          , descTs closeDoorTriggers
          , AlterDir closeDoorTriggers ))
  , ("%", ([CmdMinimal, CmdMeta], "yell/yawn", Yell))

  -- Item menu, first part of item use commands
  , ("comma", grabItems "")
  , ("d", dropItems "drop item(s)")
  , ("period", dropItems "")
  , ("f", addCmdCategory CmdItemMenu $ projectA flingTs)
  , ("C-f", addCmdCategory CmdItemMenu
            $ replaceDesc "auto-fling and keep choice"
            $ projectI flingTs)
  , ("a", addCmdCategory CmdItemMenu $ applyI applyTs)
  , ("C-a", addCmdCategory CmdItemMenu
            $ replaceDesc "apply and keep choice" $ applyIK applyTs)
  , ("p", moveItemTriple [CGround, CEqp, CSha] CInv
                         "item" False)
  , ("i", replaceDesc "" $ moveItemTriple [CGround, CEqp, CSha] CInv
                                          "item" False)
  , ("e", moveItemTriple [CGround, CInv, CSha] CEqp
                         "item" False)
  , ("s", moveItemTriple [CGround, CInv, CEqp] CSha
                         "and share item" False)

  -- Terrain exploration and alteration
  , ("C", ([CmdMove], "open or close or alter", AlterDir []))
  , ("=", ( [CmdMove], "select (or deselect) party member", SelectActor) )
  , ("_", ([CmdMove], "deselect (or select) all on the level", SelectNone))
  , ("semicolon", ( [CmdMove]
                  , "go to x-hair for 25 steps"
                  , Macro ["C-semicolon", "C-quotedbl", "C-V"] ))
  , ("colon", ( [CmdMove]
              , "run to x-hair collectively for 25 steps"
              , Macro ["C-colon", "C-quotedbl", "C-V"] ))
  , ("x", ( [CmdMove]
          , "explore nearest unknown spot"
          , autoexploreCmd ))
  , ("X", ( [CmdMove]
          , "autoexplore 25 times"
          , autoexplore25Cmd ))
  , ("R", ([CmdMove], "rest (wait 25 times)", Macro ["KP_Begin", "C-V"]))
  , ("C-R", ( [CmdMove], "heed (lurk 0.1 turns 100 times)"
            , Macro ["C-KP_Begin", "V"] ))

  -- Item use, continued
  , ("P", ( [CmdItem, CmdDashboard]
          , "manage inventory pack of the leader"
          , ChooseItemMenu (MStore CInv) ))
  , ("I", ( [CmdItem, CmdDashboard]
          , ""
          , ChooseItemMenu (MStore CInv) ))
  , ("S", ( [CmdItem, CmdDashboard]
          , "manage the shared party stash"
          , ChooseItemMenu (MStore CSha) ))
  , ("G", ( [CmdItem, CmdDashboard]
          , "manage items on the ground"
          , ChooseItemMenu (MStore CGround) ))
  , ("A", ( [CmdItem, CmdDashboard]
          , "manage all owned items"
          , ChooseItemMenu MOwned ))
  , ("@", ( [CmdItem, CmdDashboard]
          , "describe organs of the leader"
          , ChooseItemMenu MOrgans ))
  , ("#", ( [CmdItem, CmdDashboard]
          , "show skill summary of the leader"
          , ChooseItemMenu MSkills ))
  , ("~", ( [CmdItem]
          , "display known lore"
          , ChooseItemMenu (MLore SItem) ))

  -- Dashboard, in addition to commands marked above
  , ("safeD0", ([CmdInternal, CmdDashboard], "", Cancel))  -- blank line
  ]
  ++
  map (\(k, slore) -> ("safeD" ++ show (k :: Int)
                      , ( [CmdInternal, CmdDashboard]
                        , "display" <+> ppSLore slore <+> "lore"
                        , ChooseItemMenu (MLore slore) )))
      (zip [1..] [minBound..maxBound])
  ++
  [ ("safeD98", ( [CmdInternal, CmdDashboard]
                , "display place lore"
                , ChooseItemMenu MPlaces) )
  , ("safeD99", ([CmdInternal, CmdDashboard], "", Cancel))  -- blank line

  -- Aiming
  , ("!", ([CmdAim], "", AimEnemy))
  , ("/", ([CmdAim], "", AimItem))
  , ("+", ([CmdAim], "swerve the aiming line", EpsIncr True))
  , ("-", ([CmdAim], "unswerve the aiming line", EpsIncr False))
  , ("\\", ([CmdAim], "cycle aiming modes", AimFloor))
  , ("C-?", ( [CmdAim]
            , "set x-hair to nearest unknown spot"
            , XhairUnknown ))
  , ("C-/", ( [CmdAim]
            , "set x-hair to nearest item"
            , XhairItem ))
  , ("C-{", ( [CmdAim]
            , "set x-hair to nearest upstairs"
            , XhairStair True ))
  , ("C-}", ( [CmdAim]
            , "set x-hair to nearest dnstairs"
            , XhairStair False ))
  , ("<", ([CmdAim], "move aiming one level up" , AimAscend 1))
  , ("C-<", ( [CmdNoHelp], "move aiming 10 levels up"
            , AimAscend 10) )
  , (">", ([CmdAim], "move aiming one level down", AimAscend (-1)))
      -- 'lower' would be misleading in some games, just as 'deeper'
  , ("C->", ( [CmdNoHelp], "move aiming 10 levels down"
            , AimAscend (-10)) )
  , ("BackSpace" , ( [CmdAim]
                   , "clear chosen item and x-hair"
                   , ComposeUnlessError ClearTargetIfItemClear ItemClear))

  -- Assorted
  , ("F12", ([CmdMeta], "open dashboard", Dashboard))
  , ("?", ([CmdMeta], "display help", Hint))
  , ("F1", ([CmdMeta, CmdDashboard], "display help immediately", Help))
  , ("v", ([CmdMeta], "voice again the recorded commands", Repeat 1))
  , ("V", repeatTriple 100)
  , ("C-v", repeatTriple 1000)
  , ("C-V", repeatTriple 25)
  , ("'", ([CmdMeta], "start recording commands", Record))
  , ("C-S", ([CmdMeta], "save game backup", GameSave))
  , ("C-c", ([CmdMeta], "exit without saving", GameDrop))
  , ("C-P", ([CmdMeta], "print screen", PrintScreen))

  -- Dashboard, in addition to commands marked above
  , ("safeD101", ([CmdInternal, CmdDashboard], "display history", AllHistory))

  -- Mouse
  , ( "LeftButtonRelease"
    , mouseLMB goToCmd
               "go to pointer for 25 steps/fling at enemy" )
  , ( "S-LeftButtonRelease"
    , mouseLMB runToAllCmd
               "run to pointer collectively for 25 steps/fling at enemy" )
  , ("RightButtonRelease", mouseRMB)
  , ("C-LeftButtonRelease", replaceDesc "" mouseRMB)  -- Mac convention
  , ( "C-RightButtonRelease"
    , ([CmdMouse], "open or close or alter at pointer", AlterWithPointer []) )
  , ("MiddleButtonRelease", mouseMMB)
  , ("WheelNorth", ([CmdMouse], "swerve the aiming line", Macro ["+"]))
  , ("WheelSouth", ([CmdMouse], "unswerve the aiming line", Macro ["-"]))

  -- Debug and others not to display in help screens
  , ("C-semicolon", ( [CmdNoHelp]
                    , "move one step towards the x-hair"
                    , MoveOnceToXhair ))
  , ("C-colon", ( [CmdNoHelp]
                , "run collectively one step towards the x-hair"
                , RunOnceToXhair ))
  , ("C-quotedbl", ( [CmdNoHelp]
                   , "continue towards the x-hair"
                   , ContinueToXhair ))
  , ("C-comma", ([CmdNoHelp], "run once ahead", RunOnceAhead))
  , ("safe1", ( [CmdInternal]
              , "go to pointer for 25 steps"
              , goToCmd ))
  , ("safe2", ( [CmdInternal]
              , "run to pointer collectively"
              , runToAllCmd ))
  , ("safe3", ( [CmdInternal]
              , "pick new leader on screen"
              , PickLeaderWithPointer ))
  , ("safe4", ( [CmdInternal]
              , "select party member on screen"
              , SelectWithPointer ))
  , ("safe5", ( [CmdInternal]
              , "set x-hair to enemy"
              , AimPointerEnemy ))
  , ("safe6", ( [CmdInternal]
              , "fling at enemy under pointer"
              , aimFlingCmd ))
  , ("safe7", ( [CmdInternal, CmdDashboard]
              , "open main menu"
              , MainMenuAutoOff ))
  , ("safe8", ( [CmdInternal]
              , "cancel aiming"
              , Cancel ))
  , ("safe9", ( [CmdInternal]
              , "accept target"
              , Accept ))
  , ("safe10", ( [CmdInternal]
               , "wait a turn, bracing for impact"
               , Wait ))
  , ("safe11", ( [CmdInternal]
               , "lurk 0.1 of a turn"
               , Wait10 ))
  , ("safe12", ( [CmdInternal]
               , "snap x-hair to enemy"
               , XhairPointerEnemy ))
  ]
  ++ map defaultHeroSelect [0..6]

closeDoorTriggers :: [TriggerTile]
closeDoorTriggers =
  [ TriggerTile { ttverb = "close"
                , ttobject = "door"
                , ttfeature = TK.CloseTo "closed vertical door Lit" }
  , TriggerTile { ttverb = "close"
                , ttobject = "door"
                , ttfeature = TK.CloseTo "closed horizontal door Lit" }
  , TriggerTile { ttverb = "close"
                , ttobject = "door"
                , ttfeature = TK.CloseTo "closed vertical door Dark" }
  , TriggerTile { ttverb = "close"
                , ttobject = "door"
                , ttfeature = TK.CloseTo "closed horizontal door Dark" }
  ]

applyTs :: [TriggerItem]
applyTs = [TriggerItem { tiverb = "apply"
                       , tiobject = "consumable"
                       , tisymbols = "!,?/" }]
