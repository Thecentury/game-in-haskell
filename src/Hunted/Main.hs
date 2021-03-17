import Hunted.Backend
import Hunted.Graphics
import Hunted.Game

import System.Exit ( exitSuccess )
import System.Random
import Control.Concurrent (threadDelay)
import Control.Monad (unless, join)
import Control.Monad.Fix (fix)
import FRP.Elerea.Simple as Elerea

width :: Int
width = 640

height :: Int
height = 480

main :: IO ()
main = do
    (directionKeyGen, directionKeySink) <- external (False, False, False, False)
    (shootKeyGen, shootKeySink) <- external (False, False, False, False)
    (windowSizeGen,windowSizeSink) <- external (fromIntegral width, fromIntegral height)
    randomGenerator <- newStdGen
    glossState <- initState
    textures <- loadTextures
    withWindow width height windowSizeSink "hunted" $ \win -> do
        network <- start $ do
          directionKey <- directionKeyGen
          windowSize <- windowSizeGen
          shootKey <- shootKeyGen
          hunted win windowSize directionKey shootKey randomGenerator textures glossState
        fix $ \loop -> do
              readInput win directionKeySink shootKeySink
              join network
              threadDelay 20000
              esc <- exitKeyPressed win
              unless esc loop
        exitSuccess
