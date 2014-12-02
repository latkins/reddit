module Reddit.Login
  ( login ) where

import Reddit.Types.Error
import Reddit.Types.Reddit

import Control.Concurrent (threadDelay)
import Control.Concurrent.STM.TVar
import Control.Exception (try)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Trans.Either
import Control.Monad.Trans.State
import Data.Bifunctor (first)
import Data.Text (Text)
import Network.API.Builder
import Network.HTTP.Conduit

loginRoute :: Text -> Text -> Route
loginRoute user pass = Route [ "api", "login" ]
                             [ "rem" =. True
                             , "user" =. user
                             , "passwd" =. pass ]
                             "POST"

getLoginDetails :: MonadIO m => Text -> Text -> RedditT m LoginDetails
getLoginDetails user pass = do
  b <- RedditT $ liftBuilder get
  req <- RedditT $ hoistEither $ case routeRequest b (loginRoute user pass) of
    Just url -> Right url
    Nothing -> Left InvalidURLError
  resp <- liftIO $ try $ withManager $ httpLbs req
  resp' <- RedditT $ hoistEither $ first HTTPError resp
  let cj = responseCookieJar resp'
  mh <- nest $ RedditT $ hoistEither $ decode $ responseBody resp'
  case mh of
    Left x@(APIError (RateLimitError wait _)) -> do
      RateLimits limiting _ <- RedditT $ liftState get >>= liftIO . readTVarIO
      if limiting
        then do
          liftIO $ threadDelay $ (fromIntegral wait + 5) * 1000000
          getLoginDetails user pass
        else RedditT $ hoistEither $ Left x
    Left x -> RedditT $ hoistEither $ Left x
    Right modhash -> return $ LoginDetails modhash cj

login :: MonadIO m => Text -> Text -> RedditT m LoginDetails
login user pass = do
  RedditT $ baseURL loginBaseURL
  d <- getLoginDetails user pass
  RedditT $ baseURL mainBaseURL
  return d