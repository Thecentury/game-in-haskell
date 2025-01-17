{-# LANGUAGE PackageImports, RecursiveDo, ExtendedDefaultRules #-}
{-# OPTIONS_GHC -fno-warn-type-defaults #-}
import "GLFW-b" Graphics.UI.GLFW as GLFW
import Graphics.Gloss
import Graphics.Gloss.Rendering
import Graphics.Gloss.Data.ViewPort
import System.Exit ( exitSuccess )
import Control.Concurrent (threadDelay)
import Control.Monad (when, unless, join)
import Control.Monad.Fix (fix)
import FRP.Elerea.Simple
import System.Random

type Pos = Point
data Player = Player { position :: Pos, movement :: Maybe PlayerMovement }
               deriving Show
data PlayerMovement = PlayerMovement { dir :: Direction, step :: WalkStage }
               deriving Show
data Monster = Monster Pos MonsterStatus
               deriving Show

data MonsterStatus = Wander Direction Int
                   | Hunting HuntingDirection
               deriving Show
data Direction = WalkUp | WalkDown | WalkLeft | WalkRight
                 deriving (Show, Enum, Bounded)

data HuntingDirection = HuntingRight | HuntingLeft
                        deriving Show

instance Random Direction where
  randomR (a, b) g = case randomR (fromEnum a, fromEnum b) g of
                       (x, g') -> (toEnum x, g')
  random g = randomR (minBound, maxBound) g

data TextureSet = TextureSet { front :: Picture, back :: Picture, left :: Picture, right :: Picture }
                | PlayerTextureSet { fronts :: WalkingTexture, backs :: WalkingTexture, lefts :: WalkingTexture, rights :: WalkingTexture }

data WalkingTexture = WalkingTexture { neutral :: Picture, walkLeft :: Picture, walkRight :: Picture }

data WalkStage = One | Two | Three | Four
                 deriving (Show, Eq, Enum, Bounded)

data Textures = Textures { texturesBackground :: Picture
                         , texturesPlayer :: TextureSet
                         , texturesMonsterWalking :: TextureSet
                         , texturesMonsterHunting :: TextureSet }

initialPlayer :: Player
initialPlayer = Player (0, 0) Nothing

initialMonster :: Monster
initialMonster = Monster (200, 200) (Wander WalkUp wanderDist)

initialViewport :: ViewPort
initialViewport = ViewPort { viewPortTranslate = (0, 0), viewPortRotate = 0, viewPortScale = viewportScale }

viewportScale :: Float
viewportScale = 4

width :: Int
width = 640

height :: Int
height = 480

worldWidth :: Float
worldWidth = 2560

worldHeight :: Float
worldHeight = 1920

playerSize, monsterSize, monsterSpeed :: Float
playerSize = 20
monsterSize = 20
monsterSpeed = 5

main :: IO ()
main = do
    (directionKeyGen, directionKeySink) <- external (False, False, False, False)
    randomGenerator <- newStdGen
    glossState <- initState
    textures <- loadTextures
    withWindow width height "Game-Demo" $ \win -> do
          network <- start $ do
            directionKey <- directionKeyGen
            hunted win directionKey randomGenerator textures glossState
          fix $ \loop -> do
               readInput win directionKeySink
               join network
               threadDelay 20000
               esc <- keyIsPressed win Key'Escape
               unless esc loop
          exitSuccess

loadTextures :: IO Textures
loadTextures = do
    playerTextureSet <- PlayerTextureSet <$> loadAnims "images/knight-front.bmp" "images/knight-front-1.bmp" "images/knight-front-3.bmp"
                                         <*> loadAnims "images/knight-back.bmp" "images/knight-back-1.bmp" "images/knight-back-3.bmp"
                                         <*> loadAnims "images/knight-left.bmp" "images/knight-left-1.bmp" "images/knight-left-3.bmp"
                                         <*> loadAnims "images/knight-right.bmp" "images/knight-right-1.bmp" "images/knight-right-3.bmp"
    monsterWalkingSet <- TextureSet <$> loadBMP "images/monster-walking-front.bmp"
                                    <*> loadBMP "images/monster-walking-back.bmp"
                                    <*> loadBMP "images/monster-walking-left.bmp"
                                    <*> loadBMP "images/monster-walking-right.bmp"
    -- moves diagonally, so only 2 textures needed technically
    monsterHuntingSet <- TextureSet <$> loadBMP "images/monster-hunting-left.bmp"
                                    <*> loadBMP "images/monster-hunting-right.bmp"
                                    <*> loadBMP "images/monster-hunting-left.bmp"
                                    <*> loadBMP "images/monster-hunting-right.bmp"
    backgroundTexture <- loadBMP "images/background-tile.bmp"
    return Textures { texturesBackground = backgroundTexture
                    , texturesPlayer = playerTextureSet
                    , texturesMonsterWalking = monsterWalkingSet
                    , texturesMonsterHunting = monsterHuntingSet }

loadAnims :: String -> String -> String -> IO WalkingTexture
loadAnims path1 path2 path3 = WalkingTexture <$> loadBMP path1 <*> loadBMP path2 <*> loadBMP path3

hunted :: RandomGen t =>
          Window
          -> Signal (Bool, Bool, Bool, Bool)
          -> t
          -> Textures
          -> State
          -> SignalGen (Signal (IO ()))
hunted win directionKey randomGenerator textures glossState = mdo
    player <- transfer2 initialPlayer (movePlayer 10) directionKey gameOver'
    randomNumber <- stateful (undefined, randomGenerator) nextRandom
    monster <- transfer3 initialMonster wanderOrHunt player randomNumber gameOver'
    gameOver <- memo (playerEaten <$> player <*> monster)
    gameOver' <- delay False gameOver
    viewport <- transfer initialViewport viewPortMove player
    return $ renderFrame win glossState textures <$> player <*> monster <*> gameOver <*> viewport
    where playerEaten player monster = distance player monster < 10^(2 :: Integer)
          nextRandom (_, g) = random g

viewPortMove :: Player -> ViewPort -> ViewPort
viewPortMove (Player (x,y) _) (ViewPort { viewPortTranslate = _, viewPortRotate = rotation, viewPortScale = scaled }) =
        ViewPort { viewPortTranslate = (-x, -y), viewPortRotate = rotation, viewPortScale = scaled }

readInput :: Window -> ((Bool, Bool, Bool, Bool) -> IO ()) -> IO ()
readInput window directionKeySink = do
    pollEvents
    l <- keyIsPressed window Key'Left
    r <- keyIsPressed window Key'Right
    u <- keyIsPressed window Key'Up
    d <- keyIsPressed window Key'Down
    directionKeySink (l, r, u, d)

movePlayer :: Float -> (Bool, Bool, Bool, Bool) -> Bool -> Player -> Player
movePlayer _ _ True player = player
movePlayer increment direction False player
  | outsideOfLimits (position (move direction player increment)) playerSize = player
  | otherwise = move direction player increment

outsideOfLimits :: (Float, Float) -> Float -> Bool
outsideOfLimits (xmon, ymon) size = xmon > worldWidth/2 - size/2 ||
                                    xmon < ((-worldWidth)/2 + size/2) ||
                                    ymon > worldHeight/2 - size/2 ||
                                    ymon < ((-worldHeight)/2 + size/2)

move :: (Bool, Bool, Bool, Bool) -> Player -> Float -> Player
move (True, _, _, _) (Player (xpos, ypos) (Just (PlayerMovement WalkLeft n))) increment = Player (xpos - increment, ypos) (Just $ PlayerMovement WalkLeft (circular n))
move (True, _, _, _) (Player (xpos, ypos) _) increment = Player (xpos - increment, ypos) $ Just $ PlayerMovement WalkLeft One
move (_, True, _, _) (Player (xpos, ypos) (Just (PlayerMovement WalkRight n))) increment = Player (xpos + increment, ypos) (Just $ PlayerMovement WalkRight (circular n))
move (_, True, _, _) (Player (xpos, ypos) _) increment = Player (xpos + increment, ypos) $ Just $ PlayerMovement WalkRight One
move (_, _, True, _) (Player (xpos, ypos) (Just (PlayerMovement WalkUp n))) increment = Player (xpos, (ypos + increment)) (Just $ PlayerMovement WalkUp (circular n))
move (_, _, True, _) (Player (xpos, ypos) _) increment = Player (xpos, ypos + increment) $ Just $ PlayerMovement WalkUp One
move (_, _, _, True) (Player (xpos, ypos) (Just (PlayerMovement WalkDown n))) increment = Player (xpos, (ypos - increment)) (Just $ PlayerMovement WalkDown (circular n))
move (_, _, _, True) (Player (xpos, ypos) _) increment = Player (xpos, (ypos - increment)) $ Just $ PlayerMovement WalkDown One

move (False, False, False, False) (Player (xpos, ypos) _) _ = Player (xpos, ypos) Nothing

circular :: (Eq x, Enum x, Bounded x) => x -> x
circular x = if x == maxBound then minBound else succ x

wanderDist :: Int
wanderDist = 45

huntingDist :: Float
huntingDist = 200

wanderOrHunt :: RandomGen t => Player -> (Direction, t) -> Bool -> Monster -> Monster
wanderOrHunt _ _ True monster = monster
wanderOrHunt player (r, _) False monster = if close player monster
                                                then hunt player monster
                                                else wander r monster

close :: Player -> Monster -> Bool
close player monster = distance player monster < huntingDist^2

distance :: Player -> Monster -> Float
distance (Player (xpos, ypos) _) (Monster (xmon, ymon) _) = (xpos - xmon)^2 + (ypos - ymon)^2

-- if player is upper left quadrant, diagonal left
-- means xpos > xmon and ypos > ymon
hunt :: Player -> Monster -> Monster
hunt (Player (xpos, ypos) _) (Monster (xmon, ymon) _) = Monster ((xmon + (signum (xpos - xmon))*monsterSpeed), (ymon + (signum (ypos - ymon))*monsterSpeed)) (Hunting $ huntingDirection (signum (xpos - xmon)) (signum (ypos - ymon)))

huntingDirection :: Float -> Float -> HuntingDirection
huntingDirection (-1) (-1) = HuntingLeft
huntingDirection (-1) 1 = HuntingLeft
huntingDirection 1 (-1) = HuntingRight
huntingDirection 1 1 = HuntingRight
huntingDirection (-1) _ = HuntingLeft
huntingDirection _ _ = HuntingRight

-- turn in random direction
wander :: Direction -> Monster -> Monster
wander r (Monster (xmon, ymon) (Wander _ 0)) = Monster (xmon, ymon) (Wander r wanderDist)
wander r (Monster (xmon, ymon) (Hunting _)) = Monster (xmon, ymon) (Wander r wanderDist)
-- go straight
wander _ (Monster (xmon, ymon) (Wander direction n)) = do
                   let currentDirection = continueDirection direction (outsideOfLimits (xmon, ymon) monsterSize)
                   Monster
                       (stepInCurrentDirection currentDirection (xmon, ymon) monsterSpeed)
                       (Wander currentDirection (n-1))

continueDirection :: Direction -> Bool -> Direction
continueDirection WalkUp True = WalkDown
continueDirection WalkDown True = WalkUp
continueDirection WalkLeft True = WalkRight
continueDirection WalkRight True = WalkLeft
continueDirection direction False = direction

stepInCurrentDirection :: Direction -> (Float, Float) -> Float -> (Float, Float)
stepInCurrentDirection WalkUp (xpos, ypos)    speed = (xpos, ypos + speed)
stepInCurrentDirection WalkDown (xpos, ypos)  speed = (xpos, ypos - speed)
stepInCurrentDirection WalkLeft (xpos, ypos)  speed = (xpos - speed, ypos)
stepInCurrentDirection WalkRight (xpos, ypos) speed = (xpos + speed, ypos)

renderFrame :: Window
               -> State
               -> Textures
               -> Player
               -> Monster
               -> Bool
               -> ViewPort
               -> IO ()
renderFrame window glossState textures (Player _ playerDir) (Monster (xmon, ymon) status) gameOver viewport = do
   displayPicture (width, height) black glossState (viewPortScale viewport) $
     Pictures $ gameOngoing gameOver
                             [ uncurry translate (viewPortTranslate viewport) $ tiledBackground (texturesBackground textures)
                             , renderPlayer playerDir (texturesPlayer textures)
                             , uncurry translate (viewPortTranslate viewport) $ renderMonster status xmon ymon (texturesMonsterWalking textures) (texturesMonsterHunting textures) ]
   swapBuffers window

-- tiling: pictures translated to the appropriate locations to fill up the given width and heights
-- I scaled the tile to the greatest common factor of the width and height, but it should work to fit the actual width and height
-- which potentially means translating the tiles back a bit not to go over the edge
tileSize :: Float
tileSize = 160

tiledBackground :: Picture -> Picture
tiledBackground texture = Pictures $ map (\a ->  ((uncurry translate) a) texture) $ translateMatrix worldWidth worldHeight

-- what we want: 640, 480
-- -320--x--(-160)--x--0--x--160--x--320
--      -240      -80    80      240
-- -240--x--(-80)--x--80--x--240
--      -160       0     160
translateMatrix :: Float -> Float -> [(Float, Float)]
translateMatrix w h = concat $ map (zip xTiles)
                             $ map (replicate (length xTiles)) yTiles
                      where xTiles = [lowerbound w, lowerbound w + tileSize..higherbound w]
                            yTiles = [lowerbound h, lowerbound h + tileSize..higherbound h]
                            higherbound size = size/2 - tileSize/2
                            lowerbound size = -(higherbound size)

renderPlayer :: Maybe PlayerMovement -> TextureSet -> Picture
renderPlayer (Just (PlayerMovement facing One)) textureSet = neutral $ playerDirectionTexture facing textureSet
renderPlayer (Just (PlayerMovement facing Two)) textureSet = walkLeft $ playerDirectionTexture facing textureSet
renderPlayer (Just (PlayerMovement facing Three)) textureSet = neutral $ playerDirectionTexture facing textureSet
renderPlayer (Just (PlayerMovement facing Four)) textureSet = walkRight $ playerDirectionTexture facing textureSet
renderPlayer Nothing textureSet = neutral $ fronts textureSet

playerDirectionTexture :: Direction -> TextureSet -> WalkingTexture
playerDirectionTexture WalkUp = backs
playerDirectionTexture WalkDown = fronts
playerDirectionTexture WalkLeft = lefts
playerDirectionTexture WalkRight = rights

renderMonster :: MonsterStatus -> Float -> Float -> TextureSet -> TextureSet -> Picture
renderMonster (Hunting HuntingLeft) xpos ypos _ textureSet = translate xpos ypos $ left textureSet
renderMonster (Hunting HuntingRight) xpos ypos _ textureSet = translate xpos ypos $ right textureSet
renderMonster (Wander WalkUp _) xpos ypos textureSet _ = translate xpos ypos $ back textureSet
renderMonster (Wander WalkDown _) xpos ypos textureSet _ = translate xpos ypos $ front textureSet
renderMonster (Wander WalkLeft n) xpos ypos textureSet _ = translate xpos ypos $ rotate (16* fromIntegral n) $ left textureSet
renderMonster (Wander WalkRight n) xpos ypos textureSet _ = translate xpos ypos $ rotate (16* fromIntegral n) $ right textureSet

-- adds gameover text if appropriate
gameOngoing :: Bool -> [Picture] -> [Picture]
gameOngoing gameOver pics = if gameOver then pics ++ [Color black $ translate (-100) 0 $ Scale 0.3 0.3 $ Text "Game Over"]
                                        else pics

withWindow :: Int -> Int -> String -> (GLFW.Window -> IO ()) -> IO ()
withWindow windowWidth windowHeight title f = do
    GLFW.setErrorCallback $ Just simpleErrorCallback
    r <- GLFW.init
    when r $ do
        m <- GLFW.createWindow windowWidth windowHeight title Nothing Nothing
        case m of
          (Just win) -> do
              GLFW.makeContextCurrent m
              f win
              GLFW.setErrorCallback $ Just simpleErrorCallback
              GLFW.destroyWindow win
          Nothing -> return ()
        GLFW.terminate
  where
    simpleErrorCallback e s =
        putStrLn $ unwords [show e, show s]

keyIsPressed :: Window -> Key -> IO Bool
keyIsPressed win key = isPress `fmap` GLFW.getKey win key

isPress :: KeyState -> Bool
isPress KeyState'Pressed   = True
isPress KeyState'Repeating = True
isPress _                  = False
