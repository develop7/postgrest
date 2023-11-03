{-# LANGUAGE NamedFieldPuns  #-}
{-# LANGUAGE RecordWildCards #-}

module PostgREST.Admin
  ( runAdmin
  ) where

import qualified Data.Text                 as T
import qualified Hasql.Session             as SQL
import qualified Network.HTTP.Types.Status as HTTP
import qualified Network.Wai               as Wai
import qualified Network.Wai.Handler.Warp  as Warp

import Control.Monad.Extra (whenJust)

import Network.Socket
import Network.Socket.ByteString

import PostgREST.AppState (AppState)
import PostgREST.Config   (AppConfig (..))

import qualified PostgREST.AppState as AppState

import Protolude
import Protolude.Partial (fromJust)

runAdmin :: AppConfig -> AppState -> Warp.Settings -> IO ()
runAdmin conf@AppConfig{configAdminServerPort} appState settings =
  whenJust (AppState.getSocketAdmin appState) $ \adminSocket -> do
    AppState.logWithZTime appState $ "Admin server listening on port " <> show (fromIntegral $ fromJust configAdminServerPort)
    void . forkIO $ Warp.runSettingsSocket settings adminSocket adminApp
  where
    adminApp = admin appState conf

-- | PostgREST admin application
admin :: AppState.AppState -> AppConfig -> Wai.Application
admin appState appConfig req respond  = do
  isMainAppReachable  <- isRight <$> reachMainApp appConfig (AppState.getSocketREST appState)
  isSchemaCacheLoaded <- isJust <$> AppState.getSchemaCache appState
  isConnectionUp      <-
    if configDbChannelEnabled appConfig
      then AppState.getIsListenerOn appState
      else isRight <$> AppState.usePool appState (SQL.sql "SELECT 1")

  case Wai.pathInfo req of
    ["ready"] ->
      respond $ Wai.responseLBS (if isMainAppReachable && isConnectionUp && isSchemaCacheLoaded then HTTP.status200 else HTTP.status503) [] mempty
    ["live"] ->
      respond $ Wai.responseLBS (if isMainAppReachable then HTTP.status200 else HTTP.status503) [] mempty
    _ ->
      respond $ Wai.responseLBS HTTP.status404 [] mempty

-- Try to connect to the main app socket
-- Note that it doesn't even send a valid HTTP request, we just want to check that the main app is accepting connections
-- The code for resolving the "*4", "!4", "*6", "!6", "*" special values is taken from
-- https://hackage.haskell.org/package/streaming-commons-0.2.2.4/docs/src/Data.Streaming.Network.html#bindPortGenEx
reachMainApp :: AppConfig -> Socket -> IO (Either IOException ())
reachMainApp AppConfig{..} appSock = try $ do
  withSocketsDo $ bracket (pure appSock) close sendEmpty
  where
    sendEmpty sock = void $ send sock mempty
