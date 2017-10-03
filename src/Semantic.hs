{-# LANGUAGE DataKinds, DeriveAnyClass, DeriveDataTypeable, GADTs, TypeOperators #-}
module Semantic
( parseBlobs
, parseBlob
, diffBlobPairs
, diffBlobPair
, diffTermPair
) where

import Algorithm (Diffable)
import Control.Exception
import Control.Monad ((<=<))
import Control.Monad.Error.Class
import Data.Align.Generic
import Data.Bifunctor
import Data.Blob
import Data.ByteString (ByteString)
import Data.Diff
import Data.Functor.Both as Both
import Data.Functor.Classes
import Data.Output
import Data.Record
import Data.Syntax.Algebra
import Data.Term
import Data.Typeable
import Info
import Interpreter
import qualified Language
import Parser
import Renderer
import Semantic.Task as Task

-- This is the primary interface to the Semantic library which provides two
-- major classes of functionality: semantic parsing and diffing of source code
-- blobs.
--
-- Design goals:
--   - No knowledge of the filesystem or Git.
--   - Built in concurrency where appropriate.
--   - Easy to consume this interface from other application (e.g a cmdline or web server app).

parseBlobs :: Output output => TermRenderer output -> [Blob] -> Task ByteString
parseBlobs renderer = fmap toOutput . distributeFoldMap (parseBlob renderer) . filter blobExists

-- | A task to parse a 'Blob' and render the resulting 'Term'.
parseBlob :: TermRenderer output -> Blob -> Task output
parseBlob renderer blob@Blob{..} = case (renderer, blobLanguage) of
  (ToCTermRenderer, Just Language.Markdown) -> parse markdownParser blob >>= decorate (markupSectionAlgebra blob) >>= render (renderToCTerm blob)
  (ToCTermRenderer, Just Language.Python) -> parse pythonParser blob >>= decorate (declarationAlgebra blob) >>= render (renderToCTerm blob)
  (ToCTermRenderer, Just Language.TypeScript) -> parse typescriptParser blob >>= decorate (declarationAlgebra blob) >>= render (renderToCTerm blob)
  (ToCTermRenderer, Just Language.Ruby) -> parse rubyParser blob >>= decorate (declarationAlgebra blob) >>= render (renderToCTerm blob)
  (ToCTermRenderer, lang)
    | Just syntaxParser <- lang >>= syntaxParserForLanguage ->
      parse syntaxParser blob >>= decorate (syntaxDeclarationAlgebra blob) >>= render (renderToCTerm blob)
  (JSONTermRenderer, lang)
    | Just (SomeParser parser) <- lang >>= someParser (Proxy :: Proxy '[ConstructorName, Foldable, Functor]) ->
      parse parser blob >>= decorate constructorLabel >>= render (renderJSONTerm blob)
    | Just syntaxParser <- lang >>= syntaxParserForLanguage ->
      parse syntaxParser blob >>= decorate syntaxIdentifierAlgebra >>= render (renderJSONTerm blob)
  (SExpressionTermRenderer, lang)
    | Just (SomeParser parser) <- lang >>= someParser (Proxy :: Proxy '[ConstructorName, Foldable, Functor]) ->
      parse parser blob >>= decorate constructorLabel . (Nil <$) >>= render renderSExpressionTerm
    | Just syntaxParser <- lang >>= syntaxParserForLanguage ->
      parse syntaxParser blob >>= render renderSExpressionTerm . fmap keepCategory
  _ -> throwError (SomeException (NoParserForLanguage blobPath blobLanguage))

data NoParserForLanguage = NoParserForLanguage FilePath (Maybe Language.Language)
  deriving (Eq, Exception, Ord, Show, Typeable)


diffBlobPairs :: Output output => DiffRenderer output -> [Both Blob] -> Task ByteString
diffBlobPairs renderer = fmap toOutput . distributeFoldMap (diffBlobPair renderer) . filter (any blobExists)

-- | A task to parse a pair of 'Blob's, diff them, and render the 'Diff'.
diffBlobPair :: DiffRenderer output -> Both Blob -> Task output
diffBlobPair renderer blobs = case (renderer, effectiveLanguage) of
  (OldToCDiffRenderer, Just Language.Markdown) -> run (\ blob -> parse markdownParser blob >>= decorate (markupSectionAlgebra blob)) diffTerms (renderToCDiff blobs)
  (OldToCDiffRenderer, Just Language.Python) -> run (\ blob -> parse pythonParser blob >>= decorate (declarationAlgebra blob)) diffTerms (renderToCDiff blobs)
  (OldToCDiffRenderer, Just Language.Ruby) -> run (\ blob -> parse rubyParser blob >>= decorate (declarationAlgebra blob)) diffTerms (renderToCDiff blobs)
  (OldToCDiffRenderer, lang)
    | Just syntaxParser <- lang >>= syntaxParserForLanguage ->
      run (\ blob -> parse syntaxParser blob >>= decorate (syntaxDeclarationAlgebra blob)) diffSyntaxTerms (renderToCDiff blobs)

  (ToCDiffRenderer, Just Language.Markdown) -> run (\ blob -> parse markdownParser blob >>= decorate (markupSectionAlgebra blob)) diffTerms (renderToCDiff blobs)
  (ToCDiffRenderer, Just Language.Python) -> run (\ blob -> parse pythonParser blob >>= decorate (declarationAlgebra blob)) diffTerms (renderToCDiff blobs)
  (ToCDiffRenderer, Just Language.Ruby) -> run (\ blob -> parse rubyParser blob >>= decorate (declarationAlgebra blob)) diffTerms (renderToCDiff blobs)
  (ToCDiffRenderer, Just Language.TypeScript) -> run (\ blob -> parse typescriptParser blob >>= decorate (declarationAlgebra blob)) diffTerms (renderToCDiff blobs)
  (ToCDiffRenderer, lang)
    | Just syntaxParser <- lang >>= syntaxParserForLanguage ->
      run (\ blob -> parse syntaxParser blob >>= decorate (syntaxDeclarationAlgebra blob)) diffSyntaxTerms (renderToCDiff blobs)

  (JSONDiffRenderer, Just Language.JSON) -> run (parse jsonParser) diffTerms (renderJSONDiff blobs)
  (JSONDiffRenderer, Just Language.Markdown) -> run (parse markdownParser) diffTerms (renderJSONDiff blobs)
  (JSONDiffRenderer, Just Language.Python) -> run (parse pythonParser) diffTerms (renderJSONDiff blobs)
  (JSONDiffRenderer, Just Language.Ruby) -> run (parse rubyParser) diffTerms (renderJSONDiff blobs)
  (JSONDiffRenderer, Just Language.TypeScript) -> run (parse typescriptParser) diffTerms (renderJSONDiff blobs)
  (JSONDiffRenderer, lang)
    | Just syntaxParser <- lang >>= syntaxParserForLanguage ->
      run (decorate syntaxIdentifierAlgebra <=< parse syntaxParser) diffSyntaxTerms (renderJSONDiff blobs)

  (PatchDiffRenderer, lang)
    | Just (SomeParser parser) <- lang >>= someParser (Proxy :: Proxy '[Diffable, Eq1, Foldable, Functor, GAlign, Show1, Traversable]) ->
      run (parse parser) diffTerms (renderPatch blobs)
    | Just syntaxParser <- lang >>= syntaxParserForLanguage ->
      run (parse syntaxParser) diffSyntaxTerms (renderPatch blobs)

  (SExpressionDiffRenderer, lang)
    | Just (SomeParser parser) <- lang >>= someParser (Proxy :: Proxy '[ConstructorName, Diffable, Eq1, Foldable, Functor, GAlign, Show1, Traversable]) ->
      run (decorate constructorLabel <=< parse parser) diffTerms (renderSExpressionDiff . bimap keepConstructorLabel keepConstructorLabel)
    | Just syntaxParser <- lang >>= syntaxParserForLanguage ->
      run (parse syntaxParser) diffSyntaxTerms (renderSExpressionDiff . bimap keepCategory keepCategory)

  _ -> throwError (SomeException (NoParserForLanguage effectivePath effectiveLanguage))
  where (effectivePath, effectiveLanguage) = case runJoin blobs of
          (Blob { blobLanguage = Just lang, blobPath = path }, _) -> (path, Just lang)
          (_, Blob { blobLanguage = Just lang, blobPath = path }) -> (path, Just lang)
          (Blob { blobPath = path }, _)                           -> (path, Nothing)

        run :: Functor syntax => (Blob -> Task (Term syntax ann)) -> (Term syntax ann -> Term syntax ann -> Diff syntax ann ann) -> (Diff syntax ann ann -> output) -> Task output
        run parse diff renderer = distributeFor blobs parse >>= runBothWith (diffTermPair blobs diff) >>= render renderer

-- | A task to diff a pair of 'Term's, producing insertion/deletion 'Patch'es for non-existent 'Blob's.
diffTermPair :: Functor syntax => Both Blob -> Differ syntax ann1 ann2 -> Term syntax ann1 -> Term syntax ann2 -> Task (Diff syntax ann1 ann2)
diffTermPair blobs differ t1 t2 = case runJoin (blobExists <$> blobs) of
  (True, False) -> pure (deleting t1)
  (False, True) -> pure (inserting t2)
  _ -> time "diff" logInfo $ diff differ t1 t2
  where
    logInfo = let (a, b) = runJoin blobs in
            [ ("before_path", blobPath a)
            , ("before_language", maybe "" show (blobLanguage a))
            , ("after_path", blobPath b)
            , ("after_language", maybe "" show (blobLanguage b)) ]


keepCategory :: HasField fields Category => Record fields -> Record '[Category]
keepCategory = (:. Nil) . category

keepConstructorLabel :: Record (ConstructorLabel ': fields) -> Record '[ConstructorLabel]
keepConstructorLabel = (:. Nil) . rhead
