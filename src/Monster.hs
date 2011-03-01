module Monster where

import Data.Char
import Data.Binary
import Control.Monad

import Geometry
import Display
import Item
import Random
import qualified Config

-- | Hit points of the hero. Experimentally balanced for multiple heroes.
heroHP :: Config.CP -> Int
heroHP config =
  let b = Config.get config "heroes" "baseHp"
      k = Config.get config "heroes" "extraHeroes"
  in  b `div` (k + 1)

-- | Time a hero can be traced by monsters. TODO: Make configurable.
smellTimeout :: Time
smellTimeout = 1000

-- | Initial hero.
defaultHero :: Int -> Loc -> Int -> Hero
defaultHero n ploc hp =
  Monster (Hero n) hp hp Nothing TNone ploc [] 'a' 10 0

-- | The serial number of the hero. At this number he appears
-- in level hero intmaps. TODO: strengthen the type to avoid the error?
heroNumber :: Hero -> Int
heroNumber pl = case mtype pl of
                    Hero k -> k
                    _ -> error "heroNumber"

type Hero = Monster

data Monster = Monster
                { mtype   :: !MonsterType,
                  mhpmax  :: !Int,
                  mhp     :: !Int,
                  mdir    :: Maybe Dir,  -- for monsters: the dir the monster last moved;
                                         -- for heroes: the dir the hero is running
                  mtarget :: Target,
-- TODO:          mper    :: Maybe Perception  -- see https://github.com/Mikolaj/LambdaHack/issues/issue/31
                  mloc    :: !Loc,
                  mitems  :: [Item],     -- inventory
                  mletter :: !Char,      -- next inventory letter
                  mspeed  :: !Time,      -- speed (i.e., delay before next action)
                  mtime   :: !Time }     -- time of next action
  deriving Show

instance Binary Monster where
  put (Monster mt mhpm mhp md tgt ml minv mletter mspeed mtime) =
    do
      put mt
      put mhpm
      put mhp
      put md
      put tgt
      put ml
      put minv
      put mletter
      put mspeed
      put mtime
  get = do
          mt      <- get
          mhpm    <- get
          mhp     <- get
          md      <- get
          tgt     <- get
          ml      <- get
          minv    <- get
          mletter <- get
          mspeed  <- get
          mtime   <- get
          return (Monster mt mhpm mhp md tgt ml minv mletter mspeed mtime)

data MonsterType =
    Hero Int
  | Eye
  | FastEye
  | Nose
  deriving (Show, Eq)

instance Binary MonsterType where
  put (Hero n) = putWord8 0 >> put n
  put Eye        = putWord8 1
  put FastEye    = putWord8 2
  put Nose       = putWord8 3
  get = do
          tag <- getWord8
          case tag of
            0 -> liftM Hero get
            1 -> return Eye
            2 -> return FastEye
            3 -> return Nose
            _ -> fail "no parse (MonsterType)"

data Target =
    TEnemy Int  -- ^ fire at a monster (or a hero) with the given number
                -- TODO: what is the monster's number?
                -- (can't be position of monster on lmonsters.
                -- because monster death invalidates that)
  | TLoc Loc    -- ^ fire at a location, if in LOS
  | TClosest    -- ^ fire at the closest enemy in LOS
  | TShare      -- ^ fire at the closest friend's target in LOS
  | TNone       -- ^ request manual targeting
  deriving (Show, Eq)

instance Binary Target where
  put (TEnemy n) = putWord8 0 >> put n
  put (TLoc loc) = putWord8 1 >> put loc
  put TClosest   = putWord8 2
  put TShare     = putWord8 3
  put TNone      = putWord8 4
  get = do
          tag <- getWord8
          case tag of
            0 -> liftM TEnemy get
            1 -> liftM TLoc get
            2 -> return TClosest
            3 -> return TShare
            4 -> return TNone
            _ -> fail "no parse (Target)"

-- | Monster frequencies (TODO: should of course vary much more
-- on local circumstances).
monsterFrequency :: Frequency MonsterType
monsterFrequency =
  Frequency
  [
    (2, Nose),
    (6, Eye),
    (1, FastEye)
  ]

-- | Generate monster.
newMonster :: Loc -> Frequency MonsterType -> Rnd Monster
newMonster loc ftp =
    do
      tp <- frequency ftp
      hp <- hps tp
      let s = speed tp
      return (template tp hp loc s)
  where
    -- setting the time of new monsters to 0 makes them able to
    -- move immediately after generation; this does not seem like
    -- a bad idea, but it would certainly be "more correct" to set
    -- the time to the creation time instead
    template tp hp loc s = Monster tp hp hp Nothing TNone loc [] 'a' s 0

    hps Eye      = randomR (1,12)  -- falls in 1--4 unarmed rounds
    hps FastEye  = randomR (1,6)   -- 1--2
    hps Nose     = randomR (6,13)  -- 2--5 and in 1 round of the strongest sword

    speed Eye      = 10
    speed FastEye  = 4
    speed Nose     = 11

-- | Insert a monster in an mtime-sorted list of monsters.
-- Returns the position of the inserted monster and the new list.
insertMonster :: Monster -> [Monster] -> (Int, [Monster])
insertMonster = insertMonster' 0
  where
    insertMonster' n m []      = (n, [m])
    insertMonster' n m (m':ms)
      | mtime m <= mtime m'    = (n, m : m' : ms)
      | otherwise              = let (n', ms') = insertMonster' (n + 1) m ms
                                 in  (n', m' : ms')

viewMonster :: MonsterType -> Bool -> (Char, Attr -> Attr)
viewMonster (Hero n) r = (if n < 1 || n > 9 then '@' else head (show n),
                          if r
                            then setBG white . setFG black
                            else setBG black . setFG white)
viewMonster Eye      _ = ('e', setFG red)
viewMonster FastEye  _ = ('e', setFG blue)
viewMonster Nose     _ = ('n', setFG green)
