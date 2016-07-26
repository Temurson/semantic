  Hunk(..),
  truncatePatch
import Data.Bifunctor.Join
import Data.Functor.Both as Both
import Data.List (span, unzip)
import Data.Record
import Data.String
import Data.Text (pack)
import Data.These
import Patch
import Prologue hiding (fst, snd)
import Source hiding (break)

-- | Render a timed out file as a truncated diff.
truncatePatch :: DiffArguments -> Both SourceBlob -> Text
truncatePatch _ blobs = pack $ header blobs <> "#timed_out\nTruncating diff: timeout reached.\n"
patch :: HasField fields Range => Renderer (Record fields)
patch diff blobs = pack $ case getLast (foldMap (Last . Just) string) of
  Just c | c /= '\n' -> string <> "\n\\ No newline at end of file\n"
  where string = header blobs <> mconcat (showHunk blobs <$> hunks diff blobs)
data Hunk a = Hunk { offset :: Both (Sum Int), changes :: [Change a], trailingContext :: [Join These a] }
data Change a = Change { context :: [Join These a], contents :: [Join These a] }
rowIncrement :: Join These a -> Both (Sum Int)
rowIncrement = Join . fromThese (Sum 0) (Sum 0) . runJoin . (Sum 1 <$)
showHunk :: HasField fields Range => Both SourceBlob -> Hunk (SplitDiff a (Record fields)) -> String
showHunk blobs hunk = maybeOffsetHeader <>
  concat (showChange sources <$> changes hunk) <>
  showLines (snd sources) ' ' (maybeSnd . runJoin <$> trailingContext hunk)
        offsetHeader = "@@ -" <> offsetA <> "," <> show lengthA <> " +" <> offsetB <> "," <> show lengthB <> " @@" <> "\n"
        (lengthA, lengthB) = runJoin . fmap getSum $ hunkLength hunk
        (offsetA, offsetB) = runJoin . fmap (show . getSum) $ offset hunk
showChange :: HasField fields Range => Both (Source Char) -> Change (SplitDiff a (Record fields)) -> String
showChange sources change = showLines (snd sources) ' ' (maybeSnd . runJoin <$> context change) <> deleted <> inserted
  where (deleted, inserted) = runJoin $ pure showLines <*> sources <*> both '-' '+' <*> Join (unzip (fromThese Nothing Nothing . runJoin . fmap Just <$> contents change))
showLines :: HasField fields Range => Source Char -> Char -> [Maybe (SplitDiff leaf (Record fields))] -> String
showLine :: HasField fields Range => Source Char -> Maybe (SplitDiff leaf (Record fields)) -> Maybe String
showLine source line | Just line <- line = Just . toString . (`slice` source) $ getRange line
                     | otherwise = Nothing
header blobs = intercalate "\n" [filepathHeader, fileModeHeader, beforeFilepath, afterFilepath] <> "\n"
  where filepathHeader = "diff --git a/" <> pathA <> " b/" <> pathB
          (Nothing, Just mode) -> intercalate "\n" [ "new file mode " <> modeToDigits mode, blobOidHeader ]
          (Just mode, Nothing) -> intercalate "\n" [ "deleted file mode " <> modeToDigits mode, blobOidHeader ]
          (Just mode, Just other) | mode == other -> "index " <> oidA <> ".." <> oidB <> " " <> modeToDigits mode
            "old mode " <> modeToDigits mode1,
            "new mode " <> modeToDigits mode2,
        blobOidHeader = "index " <> oidA <> ".." <> oidB
           Just _ -> ty <> "/" <> path
        beforeFilepath = "--- " <> modeHeader "a" modeA pathA
        afterFilepath = "+++ " <> modeHeader "b" modeB pathB
        (pathA, pathB) = runJoin $ path <$> blobs
        (oidA, oidB) = runJoin $ oid <$> blobs
        (modeA, modeB) = runJoin $ blobKind <$> blobs

-- | A hunk representing no changes.
emptyHunk :: Hunk (SplitDiff a annotation)
emptyHunk = Hunk { offset = mempty, changes = [], trailingContext = [] }
hunks :: HasField fields Range => Diff a (Record fields) -> Both SourceBlob -> [Hunk (SplitDiff a (Record fields))]
  = [emptyHunk]
hunks diff blobs = hunksInRows (pure 1) $ alignDiff (source <$> blobs) diff
hunksInRows :: Both (Sum Int) -> [Join These (SplitDiff a annotation)] -> [Hunk (SplitDiff a annotation)]
nextHunk :: Both (Sum Int) -> [Join These (SplitDiff a annotation)] -> Maybe (Hunk (SplitDiff a annotation), [Join These (SplitDiff a annotation)])
nextChange :: Both (Sum Int) -> [Join These (SplitDiff a annotation)] -> Maybe (Both (Sum Int), Change (SplitDiff a annotation), [Join These (SplitDiff a annotation)])
changeIncludingContext :: [Join These (SplitDiff a annotation)] -> [Join These (SplitDiff a annotation)] -> Maybe (Change (SplitDiff a annotation), [Join These (SplitDiff a annotation)])
rowHasChanges :: Join These (SplitDiff a annotation) -> Bool
rowHasChanges row = or (hasChanges <$> row)