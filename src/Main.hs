module Main where

import Control.Monad.Error
import Control.Monad.State
import Data.Maybe (fromMaybe)
import Network.Reddit
import System.Console.CommandLoop
import System.Exit
import Data.List (isPrefixOf)
import Data.Char (toLower)
import System.Environment (getArgs)

-- | The application's context state
data RedditContext = RedditContext { subreddit :: Maybe String,
                                     pageSize  :: Int,
                                     sorting   :: Sorting,
                                     links     :: [Link] }

-- | The full list of commands available for the user
redditCommands :: [Command RedditContext]
redditCommands = [Command 0 "quit"          cmdQuit
                          "Exit the program",
                  Command 0 "next"          cmdNextPage
                          "Go to next page and list",
                  Command 0 "previous"      cmdPreviousPage
                          "Go to previous page and list",
                  Command 0 "first"         cmdFirstPage
                          "Go to first page and list",
                  Command 1 "subreddit"     cmdSubreddit
                          "Change or show subredit",
                  Command 0 "hot"           cmdSortingHot
                          "Go to the \"hot\" sorting",
                  Command 0 "new"           cmdSortingNew
                          "Go to the \"new\" sorting",
                  Command 0 "top"           cmdSortingTop
                          "Go to the \"top\" sorting",
                  Command 0 "controversial" cmdSortingControversial
                          "Go to the \"controversial\" sorting",
                  Command 1 "help"          (cmdHelp redditCommands)
                          "Display help about a command or all commands",
                  Command 1 "page"          cmdPageSize
                          "Set or display the current page size",
                  Command 0 "list"          cmdList
                          "List current page"]

-- | loads initial context and start the evaluation loop
main :: IO ()
main = loadInitialContext >>= evalExecuteLoop redditCommands (load First)

-- | Loads the initial context. Try to get from a command line arguments, history file, or creates a
--   default one
loadInitialContext :: IO RedditContext
loadInitialContext = cmdArgsContext =<< defaultContext 
    where 
        defaultContext :: IO RedditContext
        defaultContext = return $ RedditContext Nothing 12 New []
        cmdArgsContext :: (RedditContext -> IO RedditContext)
        cmdArgsContext ctx = do
            (sbrdt, srtng) <- fmap parseArgs getArgs
            return $ ctx {subreddit = sbrdt, sorting = srtng}
                where
                    parseArgs (arg:_)
                        | null sr = (Nothing, read s)
                        | otherwise = (Just sr, read s)
                        where
                            sr = takeWhile ('/' /=) arg
                            s  = drop ((length sr) + 1) arg
                    parseArgs _ = (subreddit ctx, sorting ctx)

instance Read Sorting where
	readsPrec _ str =
		case match (map toLower str) of
			(x:_)   -> [(x, "")]
			_       -> [(Hot, "")]
		where
		        values = [("hot", Hot), ("new", New),
				("top", Top), ("controversial",Controversial)]
			match :: String -> [Sorting]
			match value = map snd $ filter (isPrefixOf value . fst) values

cmdQuit :: [String] -> CommandAction RedditContext
cmdQuit _ = liftIO exitSuccess

cmdNextPage :: [String] -> CommandAction RedditContext
cmdNextPage _ =
    lift get >>= loadNext . links >> cmdList []
  where
    loadNext [] = throwError "could not go to next page from empty page"
    loadNext l = load $ After $ name $ last l

cmdPreviousPage :: [String] -> CommandAction RedditContext
cmdPreviousPage _ =
    lift get >>= loadPrev . links >> cmdList []
  where
    loadPrev [] = throwError "could not go to previous page from empty page"
    loadPrev (x:_) = load $ Before $ name x

cmdFirstPage :: [String] -> CommandAction RedditContext
cmdFirstPage _ = load First >> cmdList []

cmdSortingHot :: [String] -> CommandAction RedditContext
cmdSortingHot _ = lift (modify (\c -> c {sorting = Hot})) >> load First >> cmdList []

cmdSortingNew :: [String] -> CommandAction RedditContext
cmdSortingNew _ = lift (modify (\c -> c {sorting = New})) >> load First >> cmdList []

cmdSortingTop :: [String] -> CommandAction RedditContext
cmdSortingTop _ = lift (modify (\c -> c {sorting = Top})) >> load First >> cmdList []

cmdSortingControversial :: [String] -> CommandAction RedditContext
cmdSortingControversial _ = lift (modify (\c -> c {sorting = Controversial})) >> load First >> cmdList []

cmdPageSize :: [String] -> CommandAction RedditContext
cmdPageSize (x:_) = lift (modify (\c -> c {pageSize = read x}))
cmdPageSize [] = lift get >>= liftIO . print . pageSize

cmdSubreddit :: [String] -> CommandAction RedditContext
cmdSubreddit (x:_) = lift (modify (\c -> c {subreddit = Just x})) >> load First >> cmdList []
cmdSubreddit [] = lift get >>= liftIO . putStrLn . fromMaybe "<no subreddit>" . subreddit

cmdList :: [String] -> CommandAction RedditContext
cmdList _ =
    do ctx <- lift get
       let headerDesc = fromMaybe "" (subreddit ctx) ++ "/" ++ show (sorting ctx)
       liftIO $ do putStrLn headerDesc
                   putStrLn $ replicate (length headerDesc) '='
                   printLinks $ links ctx
  where
    printLinks [] = return ()
    printLinks (l:ls) = do putStrLn $ title l
                           putStrLn $ url l
                           putStrLn ""
                           printLinks ls

load :: Page -> CommandAction RedditContext
load page = do ctx <- lift get
               liftIO (runErrorT $ listing (subreddit ctx) page (sorting ctx) $ pageSize ctx) >>=
                either throwError (\(Listing ls) -> lift $ modify $ \c -> c { links = ls })

