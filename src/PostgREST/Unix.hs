module PostgREST.Unix
  ( installSignalHandlers
  , createAndBindSocket
  ) where

import qualified System.Posix.Signals     as Signals
import           System.Posix.Types       (FileMode)
import           System.PosixCompat.Files (setFileMode)

import           Data.String      (String)
import qualified Network.Socket   as NS
import           Protolude
import           System.Directory (removeFile)
import           System.IO.Error  (isDoesNotExistError)

-- | Set signal handlers, only for systems with signals
installSignalHandlers :: ThreadId -> IO () -> IO () -> IO ()
installSignalHandlers tid usr1 usr2 = do
  let interrupt = throwTo tid UserInterrupt
  install Signals.sigINT interrupt
  install Signals.sigTERM interrupt
  install Signals.sigUSR1 usr1
  install Signals.sigUSR2 usr2
  where
    install signal handler =
      void $ Signals.installHandler signal (Signals.Catch handler) Nothing

createAndBindSocket :: String -> FileMode -> IO NS.Socket
createAndBindSocket path mode = do
  deleteSocketFileIfExist path
  sock <- NS.socket NS.AF_UNIX NS.Stream NS.defaultProtocol
  NS.bind sock $ NS.SockAddrUnix path
  NS.listen sock (max 2048 NS.maxListenQueue)
  setFileMode path mode
  return sock
  where
    deleteSocketFileIfExist path' =
      removeFile path' `catch` handleDoesNotExist
    handleDoesNotExist e
      | isDoesNotExistError e = return ()
      | otherwise = throwIO e
