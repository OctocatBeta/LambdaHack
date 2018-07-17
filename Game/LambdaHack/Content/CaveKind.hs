{-# LANGUAGE DeriveGeneric #-}
-- | The type of cave kinds.
module Game.LambdaHack.Content.CaveKind
  ( CaveKind(..), makeData
#ifdef EXPOSE_INTERNAL
    -- * Internal operations
  , validateSingle, validateAll
#endif
  ) where

import Prelude ()

import Game.LambdaHack.Common.Prelude

import           Control.DeepSeq
import qualified Data.Text as T
import           GHC.Generics (Generic)

import           Game.LambdaHack.Common.ContentData
import qualified Game.LambdaHack.Common.Dice as Dice
import           Game.LambdaHack.Common.Misc
import           Game.LambdaHack.Common.Point
import           Game.LambdaHack.Common.Random
import           Game.LambdaHack.Content.ItemKind (ItemKind)
import           Game.LambdaHack.Content.PlaceKind (PlaceKind)
import           Game.LambdaHack.Content.TileKind (TileKind)

-- | Parameters for the generation of dungeon levels.
-- Warning: for efficiency, avoid embedded items in any of the common tiles.
data CaveKind = CaveKind
  { csymbol         :: Char             -- ^ a symbol
  , cname           :: Text             -- ^ short description
  , cfreq           :: Freqs CaveKind   -- ^ frequency within groups
  , cXminSize       :: X                -- ^ minimal X size of the whole cave
  , cYminSize       :: Y                -- ^ minimal Y size of the whole cave
  , ccellSize       :: Dice.DiceXY      -- ^ size of a map cell holding a place
  , cminPlaceSize   :: Dice.DiceXY      -- ^ minimal size of places; for merging
  , cmaxPlaceSize   :: Dice.DiceXY      -- ^ maximal size of places; for growing
  , cdarkChance     :: Dice.Dice        -- ^ the chance a place is dark
  , cnightChance    :: Dice.Dice        -- ^ the chance the cave is dark
  , cauxConnects    :: Rational         -- ^ a proportion of extra connections
  , cmaxVoid        :: Rational
      -- ^ at most this proportion of rooms may be void
  , cminStairDist   :: Int              -- ^ minimal distance between stairs
  , cextraStairs    :: Dice.Dice        -- ^ extra stairs on top of from above
  , cdoorChance     :: Chance           -- ^ the chance of a door in an opening
  , copenChance     :: Chance           -- ^ if there's a door, is it open?
  , chidden         :: Int              -- ^ if not open, hidden one in n times
  , cactorCoeff     :: Int              -- ^ the lower, the more monsters spawn
  , cactorFreq      :: Freqs ItemKind   -- ^ actor groups to consider
  , citemNum        :: Dice.Dice        -- ^ number of initial items in the cave
  , citemFreq       :: Freqs ItemKind   -- ^ item groups to consider
  , cplaceFreq      :: Freqs PlaceKind  -- ^ place groups to consider
  , cpassable       :: Bool
      -- ^ are passable default tiles permitted
  , cdefTile        :: GroupName TileKind  -- ^ the default cave tile
  , cdarkCorTile    :: GroupName TileKind  -- ^ the dark cave corridor tile
  , clitCorTile     :: GroupName TileKind  -- ^ the lit cave corridor tile
  , cfillerTile     :: GroupName TileKind  -- ^ the filler wall
  , cfenceTileN     :: GroupName TileKind  -- ^ the outer fence N wall
  , cfenceTileE     :: GroupName TileKind  -- ^ the outer fence E wall
  , cfenceTileS     :: GroupName TileKind  -- ^ the outer fence S wall
  , cfenceTileW     :: GroupName TileKind  -- ^ the outer fence W wall
  , cfenceApart     :: Bool                -- ^ are places touching fence banned
  , clegendDarkTile :: GroupName TileKind  -- ^ the dark place plan legend
  , clegendLitTile  :: GroupName TileKind  -- ^ the lit place plan legend
  , cescapeGroup    :: Maybe (GroupName PlaceKind)  -- ^ escape, if any
  , cstairFreq      :: Freqs PlaceKind
      -- ^ place groups to consider for stairs; in this case the rarity
      --   of items in the group does not affect group choice
  , cdesc           :: Text                -- ^ full cave description
  }
  deriving (Show, Generic)  -- No Eq and Ord to make extending logically sound

instance NFData CaveKind

-- | Catch caves with not enough space for all the places. Check the size
-- of the cave descriptions to make sure they fit on screen. Etc.
validateSingle :: CaveKind -> [Text]
validateSingle CaveKind{..} =
  let (minCellSizeX, minCellSizeY) = Dice.minDiceXY ccellSize
      (minMinSizeX, minMinSizeY) = Dice.minDiceXY cminPlaceSize
      (maxMinSizeX, maxMinSizeY) = Dice.maxDiceXY cminPlaceSize
      (minMaxSizeX, minMaxSizeY) = Dice.minDiceXY cmaxPlaceSize
  in [ "cname longer than 25" | T.length cname > 25 ]
     ++ [ "cXminSize < 20" | cXminSize < 20 ]
     ++ [ "cYminSize < 20" | cYminSize < 20 ]
     ++ [ "minCellSizeX < 1" | minCellSizeX < 1 ]
     ++ [ "minCellSizeY < 1" | minCellSizeY < 1 ]
     ++ [ "minCellSizeX < 6 && stairs"
        | minCellSizeX < 6 && not (null cstairFreq && isNothing cescapeGroup) ]
     ++ [ "minCellSizeY < 4 && stairs"
        | minCellSizeY < 4 && not (null cstairFreq && isNothing cescapeGroup) ]
     ++ [ "minMinSizeX < 5 && stairs"
        | minMinSizeX < 5 && not (null cstairFreq && isNothing cescapeGroup) ]
     ++ [ "minMinSizeY < 3 && stairs"
        | minMinSizeY < 3 && not (null cstairFreq && isNothing cescapeGroup) ]
     ++ [ "minMinSizeX < 1" | minMinSizeX < 1 ]
     ++ [ "minMinSizeY < 1" | minMinSizeY < 1 ]
     ++ [ "minMaxSizeX < maxMinSizeX" | minMaxSizeX < maxMinSizeX ]
     ++ [ "minMaxSizeY < maxMinSizeY" | minMaxSizeY < maxMinSizeY ]
     ++ [ "cextraStairs < 0" | Dice.minDice cextraStairs < 0 ]
     ++ [ "chidden < 0" | chidden < 0 ]
     ++ [ "cactorCoeff < 0" | cactorCoeff < 0 ]
     ++ [ "citemNum < 0" | Dice.minDice citemNum < 0 ]
     ++ [ "stairs suggested, but not defined"
        | Dice.maxDice cextraStairs > 0 && null cstairFreq ]

-- | Validate all cave kinds.
-- Note that names don't have to be unique: we can have several variants
-- of a cave with a given name.
validateAll :: ContentData ItemKind
            -> ContentData PlaceKind
            -> ContentData TileKind
            -> [CaveKind]
            -> ContentData CaveKind
            -> [Text]
validateAll coitem coplace cotile content cocave =
  let missingActorFreq = filter (not . omemberGroup coitem)
                         $ concatMap (map fst . cactorFreq) content
      missingItemFreq = filter (not . omemberGroup coitem)
                        $ concatMap (map fst . citemFreq) content
      missingPlaceFreq = filter (not . omemberGroup coplace)
                         $ concatMap (map fst . cplaceFreq) content
      missingEscapeGroup = filter (not . omemberGroup coplace)
                           $ mapMaybe cescapeGroup content
      missingStairFreq = filter (not . omemberGroup coplace)
                         $ concatMap (map fst . cstairFreq) content
      tileGroupFuns = [ cdefTile, cdarkCorTile, clitCorTile, cfillerTile
                      , cfenceTileN, cfenceTileE, cfenceTileS, cfenceTileW
                      , clegendDarkTile, clegendLitTile ]
      g kind = map (\f -> f kind) tileGroupFuns
      missingTileFreq = filter (not . omemberGroup cotile)
                        $ concatMap g content
  in [ "cactorFreq item groups not in content:" <+> tshow missingActorFreq
     | not $ null missingActorFreq ]
     ++ [ "citemFreq item groups not in content:" <+> tshow missingItemFreq
        | not $ null missingItemFreq ]
     ++ [ "cplaceFreq place groups not in content:" <+> tshow missingPlaceFreq
        | not $ null missingPlaceFreq ]
     ++ [ "cescapeGroup place groups not in content:"
          <+> tshow missingEscapeGroup
        | not $ null missingEscapeGroup ]
     ++ [ "cstairFreq place groups not in content:" <+> tshow missingStairFreq
        | not $ null missingStairFreq ]
     ++ [ "tile groups not in content:" <+> tshow missingTileFreq
        | not $ null missingTileFreq ]
     ++ [ "no cave defined for \"default random\""
        | not $ omemberGroup cocave "default random" ]

makeData :: ContentData ItemKind
         -> ContentData PlaceKind
         -> ContentData TileKind
         -> [CaveKind]
         -> ContentData CaveKind
makeData coitem coplace cotile =
  makeContentData "CaveKind" cname cfreq validateSingle
                  (validateAll coitem coplace cotile)
