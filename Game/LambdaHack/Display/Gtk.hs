-- | Text frontend based on Gtk.
module Game.LambdaHack.Display.Gtk
  ( -- * Session data type for the frontend
    FrontendSession
    -- * The output and input operations
  , pushFrame, nextEvent
    -- * Frontend administration tools
  , frontendName, startup, shutdown
  ) where

import Control.Monad
import Control.Monad.STM
import Control.Concurrent hiding (Chan)
import Control.Concurrent.STM.TBChan
import Graphics.UI.Gtk.Gdk.Events  -- TODO: replace, deprecated
import Graphics.UI.Gtk hiding (Point)
import qualified Data.List as L
import Data.IORef
import qualified Data.Map as M
import qualified Data.ByteString.Char8 as BS
import Data.Maybe

import qualified Game.LambdaHack.Key as K (Key(..), keyTranslate)
import qualified Game.LambdaHack.Color as Color

-- | Session data maintained by the frontend.
data FrontendSession = FrontendSession
  { sview       :: TextView                  -- ^ the widget to draw to
  , stags       :: M.Map Color.Attr TextTag  -- ^ text color tags for fore/back
  , schanKey    :: TBChan String             -- ^ channel for keyboard input
  , schanScreen :: TBChan (Maybe Color.SingleFrame)
                                             -- ^ channel for screen output
  }

-- | The name of the frontend.
frontendName :: String
frontendName = "gtk"

-- | Starts the main program loop using the frontend input and output.
startup :: String -> (FrontendSession -> IO ()) -> IO ()
startup configFont k = do
  -- initGUI
  unsafeInitGUIForThreadedRTS
  w <- windowNew
  ttt <- textTagTableNew
  -- text attributes
  stags <- fmap M.fromList $
             mapM (\ ak -> do
                      tt <- textTagNew Nothing
                      textTagTableAdd ttt tt
                      doAttr tt ak
                      return (ak, tt))
               [ Color.Attr{fg, bg}
               | fg <- [minBound..maxBound], bg <- Color.legalBG ]
  -- text buffer
  tb <- textBufferNew (Just ttt)
  textBufferSetText tb (unlines (replicate 25 (replicate 80 ' ')))
  -- create text view, TODO: use GtkLayout or DrawingArea instead of TextView?
  sview <- textViewNewWithBuffer tb
  containerAdd w sview
  textViewSetEditable sview False
  textViewSetCursorVisible sview False
  -- font
  f <- fontDescriptionFromString configFont
  widgetModifyFont sview (Just f)
  currentfont <- newIORef f
  let buttonPressHandler e = case e of
        Button { Graphics.UI.Gtk.Gdk.Events.eventButton = RightButton } -> do
          fsd <- fontSelectionDialogNew "Choose font"
          cf  <- readIORef currentfont  -- TODO: "Terminus,Monospace" fails
          fds <- fontDescriptionToString cf
          fontSelectionDialogSetFontName fsd fds
          fontSelectionDialogSetPreviewText fsd "eee...@.##+##"
          resp <- dialogRun fsd
          when (resp == ResponseOk) $ do
            fn <- fontSelectionDialogGetFontName fsd
            case fn of
              Just fn' -> do
                fd <- fontDescriptionFromString fn'
                writeIORef currentfont fd
                widgetModifyFont sview (Just fd)
              Nothing  -> return ()
          widgetDestroy fsd
          return True
        _ -> return False
  onButtonPress sview buttonPressHandler
  -- modify default colours
  let black = Color minBound minBound minBound  -- Color.defBG == Color.Black
      white = Color 0xC500 0xBC00 0xB800        -- Color.defFG == Color.White
  widgetModifyBase sview StateNormal black
  widgetModifyText sview StateNormal white
  -- Set up the channel for keyboard input.
  schanKey <- newTBChanIO 3
  -- Set up the channel for drawing frames.
  -- TODO: perhaps increase the channel bound and use it to report
  -- excessive animation lag and reset buffers and abort player commands.
  -- The current low frame bound value (20, 2 player turns)
  -- is intended to improve fairness.
  schanScreen <- newTBChanIO 20
  let sess = FrontendSession{..}
  -- Fork the game logic thread.
  forkIO $ k sess
  -- Fork the frame drawing thread.
  forkIO $ waitForFrames sess
  -- Fill the keyboard channel.
  onKeyPress sview
    (\ e -> do
       let kn = Graphics.UI.Gtk.Gdk.Events.eventKeyName e
       unless (deadKey kn) $ atomically $ do
         -- Key pressed. Flush all old frames up to the bound limit.
         flushChan schanScreen
         -- Ignore keypresses over the channel bound.
         -- TODO: this does not work, because game logic thread
         -- is fast enough to comsume all and only frames lag behind.
         void $ tryWriteTBChan schanKey kn
       return True)
  -- Set the quit handler.
  onDestroy w mainQuit
  -- Start it up.
  widgetShowAll w
  yield
  mainGUI

-- | Shuts down the frontend cleanly.
shutdown :: FrontendSession -> IO ()
shutdown _ = mainQuit

-- | Output to the screen via the frontend.
display :: FrontendSession    -- ^ frontend session data
        -> Color.SingleFrame  -- ^ the screen frame to draw
        -> IO ()
display FrontendSession{sview, stags} (memo, msg, status) = do
  tb <- textViewGetBuffer sview
  let attrs = L.zip [0..] $ L.map (L.map fst) memo
      chars = L.map (BS.pack . L.map snd) memo
      bs    = [BS.pack msg, BS.pack "\n", BS.unlines chars, BS.pack status]
  textBufferSetByteString tb (BS.concat bs)
  mapM_ (setTo tb stags 0) attrs

setTo :: TextBuffer -> M.Map Color.Attr TextTag -> Int -> (Int, [Color.Attr])
      -> IO ()
setTo _  _   _  (_,  [])         = return ()
setTo tb tts lx (ly, attr:attrs) = do
  ib <- textBufferGetIterAtLineOffset tb (ly + 1) lx
  ie <- textIterCopy ib
  let setIter :: Color.Attr -> Int -> [Color.Attr] -> IO ()
      setIter previous repetitions [] = do
        textIterForwardChars ie repetitions
        when (previous /= Color.defaultAttr) $
          textBufferApplyTag tb (tts M.! previous) ib ie
      setIter previous repetitions (a:as)
        | a == previous =
            setIter a (repetitions + 1) as
        | otherwise = do
            textIterForwardChars ie repetitions
            when (previous /= Color.defaultAttr) $
              textBufferApplyTag tb (tts M.! previous) ib ie
            textIterForwardChars ib repetitions
            setIter a 1 as
  setIter attr 1 attrs

flushChan :: TBChan a -> STM ()
flushChan chan = do
  m <- tryReadTBChan chan
  when (isJust m) $ flushChan chan

-- TODO: configure
-- | Maximal frames per second.
maxFps :: Int
maxFps = 10

-- TODO: perhaps rewrite all with no STM, but a single MVar
-- and hope running stops being jerky.
-- Also, perhaps make the SingleFrame type strict.
-- | Wait on the channel and draw frames on demand.
waitForFrames :: FrontendSession -> IO ()
waitForFrames sess@FrontendSession{schanScreen} = do
  -- Wait until frame received.
  mframe <- atomically $ readTBChan schanScreen
  -- Don't wait until frame drawn.
  maybe (return ()) (postGUIAsync . display sess) mframe
  threadDelay $ 1000000 `div` maxFps
  waitForFrames sess

-- | Input key via the frontend.
nextEvent :: FrontendSession -> IO K.Key
nextEvent FrontendSession{schanKey} = do
  kn <- atomically $ readTBChan schanKey
  return (K.keyTranslate kn)

-- | Add a game screen frame to the drawing channel queue.
pushFrame :: FrontendSession -> Maybe Color.SingleFrame -> IO ()
pushFrame FrontendSession{schanScreen} mframe =
  atomically $ writeTBChan schanScreen mframe

-- | Tells a dead key.
deadKey :: String -> Bool
deadKey x = case x of
  "Shift_R"          -> True
  "Shift_L"          -> True
  "Control_L"        -> True
  "Control_R"        -> True
  "Super_L"          -> True
  "Super_R"          -> True
  "Menu"             -> True
  "Alt_L"            -> True
  "Alt_R"            -> True
  "ISO_Level2_Shift" -> True
  "ISO_Level3_Shift" -> True
  "ISO_Level2_Latch" -> True
  "ISO_Level3_Latch" -> True
  "Num_Lock"         -> True
  "Caps_Lock"        -> True
  _                  -> False

doAttr :: TextTag -> Color.Attr -> IO ()
doAttr tt attr@Color.Attr{fg, bg}
  | attr == Color.defaultAttr = return ()
  | fg == Color.defFG = set tt [textTagBackground := Color.colorToRGB bg]
  | bg == Color.defBG = set tt [textTagForeground := Color.colorToRGB fg]
  | otherwise         = set tt [textTagForeground := Color.colorToRGB fg,
                                textTagBackground := Color.colorToRGB bg]
