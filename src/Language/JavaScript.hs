{-# LANGUAGE DataKinds #-}
module Language.JavaScript where

import Info
import Prologue
import Source
import Language
import qualified Syntax as S
import Term

termAssignment
  :: Source Char -- ^ The source of the term.
  -> Category -- ^ The category for the term.
  -> [ SyntaxTerm Text '[Range, Category, SourceSpan] ] -- ^ The child nodes of the term.
  -> Maybe (S.Syntax Text (SyntaxTerm Text '[Range, Category, SourceSpan])) -- ^ The resulting term, in Maybe.
termAssignment _ category children
  = case (category, children) of
    (Assignment, [ identifier, value ]) -> Just $ S.Assignment identifier value
    (MathAssignment, [ identifier, value ]) -> Just $ S.OperatorAssignment identifier value
    (MemberAccess, [ base, property ]) -> Just $ S.MemberAccess base property
    (SubscriptAccess, [ base, element ]) -> Just $ S.SubscriptAccess base element
    (CommaOperator, [ a, b ])
      | S.Indexed rest <- unwrap b
      -> Just $ S.Indexed $ a : rest
    (FunctionCall, member : args)
      | S.MemberAccess target method <- unwrap member
      -> Just $ S.MethodCall target method (toList . unwrap =<< args)
    (FunctionCall, function : args) -> Just $ S.FunctionCall function (toList . unwrap =<< args)
    (Ternary, condition : cases) -> Just $ S.Ternary condition cases
    (VarAssignment, [ x, y ]) -> Just $ S.VarAssignment x y
    (VarDecl, _) -> Just . S.Indexed $ toVarDecl <$> children
    (Object, _) -> Just . S.Object Nothing $ foldMap toTuple children
    (DoWhile, [ expr, body ]) -> Just $ S.DoWhile expr body
    (Constructor, [ expr ]) -> Just $ S.Constructor expr
    (Try, [ body ]) -> Just $ S.Try [body] [] Nothing Nothing
    (Try, [ body, catch ])
      | Catch <- Info.category (extract catch)
      -> Just $ S.Try [body] [catch] Nothing Nothing
    (Try, [ body, finally ])
      | Finally <- Info.category (extract finally)
      -> Just $ S.Try [body] [] Nothing (Just finally)
    (Try, [ body, catch, finally ])
      | Catch <- Info.category (extract catch)
      , Finally <- Info.category (extract finally)
      -> Just $ S.Try [body] [catch] Nothing (Just finally)
    (ArrayLiteral, _) -> Just $ S.Array Nothing children
    (Method, [ identifier, params, exprs ]) -> Just $ S.Method identifier Nothing (toList (unwrap params)) (toList (unwrap exprs))
    (Method, [ identifier, exprs ]) -> Just $ S.Method identifier Nothing [] (toList (unwrap exprs))
    (Class, [ identifier, superclass, definitions ]) -> Just $ S.Class identifier (Just superclass) (toList (unwrap definitions))
    (Class, [ identifier, definitions ]) -> Just $ S.Class identifier Nothing (toList (unwrap definitions))
    (Import, [ statements, identifier ] ) -> Just $ S.Import identifier (toList (unwrap statements))
    (Import, [ identifier ] ) -> Just $ S.Import identifier []
    (Export, [ statements, identifier] ) -> Just $ S.Export (Just identifier) (toList (unwrap statements))
    (Export, [ statements ] )
      | S.Indexed _ <- unwrap statements
      -> Just $ S.Export Nothing (toList (unwrap statements))
      | otherwise -> Just $ S.Export (Just statements) []
    (For, _)
      | Just (exprs, body) <- unsnoc children
      -> Just $ S.For exprs [body]
    (Function, [ body ]) -> Just $ S.AnonymousFunction [] [body]
    (Function, [ params, body ]) -> Just $ S.AnonymousFunction (toList (unwrap params)) [body]
    (Function, [ id, params, body ]) -> Just $ S.Function id (toList (unwrap params)) Nothing [body]
    _ -> Nothing

categoryForJavaScriptProductionName :: Text -> Category
categoryForJavaScriptProductionName name = case name of
  "object" -> Object
  "expression_statement" -> ExpressionStatements
  "trailing_expression_statement" -> ExpressionStatements
  "this_expression" -> Identifier
  "null" -> Identifier
  "undefined" -> Identifier
  "arrow_function" -> Function
  "generator_function" -> Function
  "math_op" -> MathOperator -- math operator, e.g. +, -, *, /.
  "bool_op" -> BooleanOperator -- boolean operator, e.g. ||, &&.
  "comma_op" -> CommaOperator -- comma operator, e.g. expr1, expr2.
  "delete_op" -> Operator -- delete operator, e.g. delete x[2].
  "type_op" -> Operator -- type operator, e.g. typeof Object.
  "void_op" -> Operator -- void operator, e.g. void 2.
  "for_statement" -> For
  "trailing_for_statement" -> For
  "for_in_statement" -> For
  "trailing_for_in_statement" -> For
  "for_of_statement" -> For
  "trailing_for_of_statement" -> For
  "new_expression" -> Constructor
  "class"  -> Class
  "catch" -> Catch
  "finally" -> Finally
  "if_statement" -> If
  "trailing_if_statement" -> If
  "empty_statement" -> Empty
  "program" -> Program
  "function_call" -> FunctionCall
  "pair" -> Pair
  "string" -> StringLiteral
  "integer" -> IntegerLiteral
  "number" -> NumberLiteral
  "float" -> FloatLiteral
  "symbol" -> SymbolLiteral
  "array" -> ArrayLiteral
  "function" -> Function
  "identifier" -> Identifier
  "formal_parameters" -> Params
  "arguments" -> Args
  "statement_block" -> ExpressionStatements
  "assignment" -> Assignment
  "member_access" -> MemberAccess
  "op" -> Operator
  "subscript_access" -> SubscriptAccess
  "regex" -> Regex
  "template_string" -> TemplateString
  "var_assignment" -> VarAssignment
  "var_declaration" -> VarDecl
  "trailing_var_declaration" -> VarDecl
  "switch_statement" -> Switch
  "math_assignment" -> MathAssignment
  "case" -> Case
  "true" -> Boolean
  "false" -> Boolean
  "ternary" -> Ternary
  "while_statement" -> While
  "trailing_while_statement" -> While
  "do_statement" -> DoWhile
  "trailing_do_statement" -> DoWhile
  "return_statement" -> Return
  "trailing_return_statement" -> Return
  "throw_statement" -> Throw
  "trailing_throw_statement" -> Throw
  "try_statement" -> Try
  "method_definition" -> Method
  "comment" -> Comment
  "bitwise_op" -> BitwiseOperator
  "rel_op" -> RelationalOperator
  "import_statement" -> Import
  "export_statement" -> Export
  "break_statement" -> Break
  "continue_statement" -> Continue
  "yield_statement" -> Yield
  _ -> Other name