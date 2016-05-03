//
//  Expr.swift
//  LispKit
//
//  Created by Matthias Zenger on 08/11/2015.
//  Copyright © 2016 ObjectHub. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import NumberKit

///
/// `Expr` represents LispKit expressions in form of an enumeration with associated values.
///
public enum Expr: Trackable, Hashable {
  case Undef
  case Void
  case Eof
  case Null
  case True
  case False
  case Sym(Symbol)
  case Fixnum(Int64)
  case Bignum(BigInt)
  case Rat(Rational<Int64>)
  case Bigrat(Rational<BigInt>)
  case Flonum(Double)
  case Complexnum(Complex<Double>)
  case Char(UniChar)
  case Str(Box<String>)
  case Vec(Vector)
  indirect case Pair(Expr, Expr)
  case Promise(Future)
  case Proc(Procedure)
  case Special(SpecialForm)
  case Var(Variable)
  case Error(AnyError)
  
  /// Returns the type of this expression.
  public var type: Type {
    switch self {
      case Undef:
        return .UndefinedType
      case Void:
        return .VoidType
      case Eof:
        return .EofType
      case Null:
        return .NullType
      case True:
        return .BooleanType
      case False:
        return .BooleanType
      case Sym(_):
        return .SymbolType
      case Fixnum(_):
        return .IntegerType
      case Bignum(_):
        return .IntegerType
      case Rat(_):
        return .RationalType
      case Bigrat(_):
        return .RationalType
      case Flonum(_):
        return .FloatType
      case Complexnum(_):
        return .ComplexType
      case Char(_):
        return .CharType
      case Str(_):
        return .StrType
      case Pair(_, _):
        return .PairType
      case Vec(_):
        return .VectorType
      case Promise(_):
        return .PromiseType
      case Special(_):
        return .SpecialType
      case Proc(_):
        return .ProcedureType
      case Var(let v):
        return v.value.type
      case Error(_):
        return .ErrorType
    }
  }
  
  // Predicate methods
  
  /// Returns true if this expression is null.
  public var isNull: Bool {
    switch self {
      case Null:
        return true
      default:
        return false
    }
  }
  
  /// Returns true if this is not the `#f` value.
  public var isTrue: Bool {
    switch self {
      case False:
        return false
      default:
        return true
    }
  }
  
  /// Returns true if this is the `#f` value.
  public var isFalse: Bool {
    switch self {
      case False:
        return true
      default:
        return false
    }
  }
  
  /// Returns true if this is an exact number.
  public var isExactNumber: Bool {
    switch self {
      case Fixnum(_), Bignum(_), Rat(_), Bigrat(_):
        return true
      default:
        return false
    }
  }
  
  /// Normalizes the representation (relevant for numeric datatypes)
  public var normalized: Expr {
    switch self {
      case Bignum(let num):
        if let fn = num.intValue {
          return Fixnum(fn)
        }
        return self
      case Rat(let num):
        if let fn = num.intValue {
          return Fixnum(fn)
        }
        return self
      case Bigrat(let num):
        if let bn = num.intValue {
          if let fn = bn.intValue {
            return Fixnum(fn)
          }
          return Bignum(bn)
        }
        return self
      case Complexnum(let num):
        return num.isReal ? Flonum(num.re) : self
      default:
        return self
    }
  }
  
  /// Returns the given expression with all symbols getting interned.
  public var datum: Expr {
    switch self {
      case Sym(let sym):
        return Sym(sym.interned)
      case Pair(let car, let cdr):
        return .Pair(car.datum, cdr.datum)
      default:
        return self
    }
  }
  
  /// Maps a list into an array of expressions and a tail (= null for proper lists)
  public func toExprs() -> (Exprs, Expr) {
    var exprs = Exprs()
    var expr = self
    while case Pair(let car, let cdr) = expr {
      exprs.append(car)
      expr = cdr
    }
    return (exprs, expr)
  }
  
  public var requiresTracking: Bool {
    switch self {
      case Vec(_), Promise(_), Proc(_), Special(_), Var(_), Error(_):
        return true
      case Pair(let car, let cdr):
        return car.requiresTracking || cdr.requiresTracking
      default:
        return false
    }
  }
  
  public func mark(tag: UInt8) {
    switch self {
      case Vec(let vector):
        vector.mark(tag)
      case Pair(let car, let cdr):
        car.mark(tag)
        cdr.mark(tag)
      case Promise(let future):
        future.mark(tag)
      case Proc(let proc):
        proc.mark(tag)
      case Special(let special):
        special.mark(tag)
      case Var(let variable):
        variable.mark(tag)
      case Error(_):
        break
      default:
        break
    }
  }
  
  public var hashValue: Int {
    var visited = Set<Vector>()
    
    func hash(expr: Expr) -> Int {
      var res: Int
      switch expr  {
        case Sym(let sym):
          res = sym.description.hashValue
        case Fixnum(let value):
          res = value.hashValue
        case Flonum(let value):
          res = value.hashValue
        case Char(let char):
          res = char.hashValue
        case Str(let str):
          res = str.value.hashValue
        case Pair(let car, let cdr):
          res = (hash(car) &* 31) + hash(cdr)
        case Vec(let vector):
          if visited.contains(vector) {
            return 0
          }
          visited.insert(vector)
          res = 0
          for expr in vector.exprs {
            res = res &* 31 + hash(expr)
          }
          visited.remove(vector)
        case Promise(let promise):
          res = promise.hashValue
        case Special(let special):
          res = special.hashValue
        case Proc(let proc):
          res = proc.hashValue
        case Var(let variable):
          res = variable.hashValue
        case Error(let err):
          res = err.hashValue
        default:
          res = 0
      }
      return res &* 31 + expr.type.hashValue
    }
    
    return hash(self)
  }
}


/// Extension adding static factory methods to `Expr`.
///
extension Expr {
  
  public static func Boolean(val: Bool) -> Expr {
    return val ? True : False
  }
  
  public static func Number(num: Int) -> Expr {
    return Fixnum(Int64(num))
  }
  
  public static func Number(num: Int64) -> Expr {
    return Fixnum(num)
  }
  
  public static func Number(num: BigInt) -> Expr {
    return Bignum(num).normalized
  }
  
  public static func Number(num: Rational<Int64>) -> Expr {
    return Rat(num).normalized
  }
  
  public static func Number(num: Rational<BigInt>) -> Expr {
    return Bigrat(num).normalized
  }
  
  public static func Number(num: Double) -> Expr {
    return Flonum(num)
  }
  
  public static func Number(num: Complex<Double>) -> Expr {
    return Complexnum(num).normalized
  }
  
  public static func List(expr: Expr...) -> Expr {
    return List(expr)
  }
  
  public static func List(exprs: Exprs, append: Expr = Expr.Null) -> Expr {
    return Expr.Stack(exprs.reverse(), append: append)
  }
  
  public static func Stack(exprs: Exprs, append: Expr = Expr.Null) -> Expr {
    var res = append
    for expr in exprs {
      res = Pair(expr, res)
    }
    return res
  }
}


/// This extension adds projections to `Expr`.
///
extension Expr {
  public func assertTypeOf(types: Type...) throws {
    for type in types {
      for subtype in type.included {
        if self.type == subtype {
          return
        }
      }
    }
    throw EvalError.TypeError(self, Set(types))
  }
  
  public func asInteger() throws -> Int64 {
    guard case Fixnum(let res) = self else {
      throw EvalError.TypeError(self, [.IntegerType])
    }
    return res
  }
  
  public func asInt() throws -> Int {
    guard case Fixnum(let res) = self else {
      throw EvalError.TypeError(self, [.IntegerType])
    }
    guard res >= 0 && res <= Int64(Int.max) else {
      throw EvalError.IndexOutOfBounds(res, Int64(Int.max), self)
    }
    return Int(res)
  }
  
  public func asFloat(coerce coerce: Bool = false) throws -> Double {
    if !coerce {
      if case Flonum(let num) = self {
        return num
      }
      throw EvalError.TypeError(self, [.FloatType])
    }
    switch self.normalized {
      case Fixnum(let num):
        return Double(num)
      case .Bignum(let num):
        return num.doubleValue
      case .Rat(let num):
        return Double(num.numerator) / Double(num.denominator)
      case .Bigrat(let num):
        return num.numerator.doubleValue / num.denominator.doubleValue
      case .Flonum(let num):
        return num
      default:
        throw EvalError.TypeError(self, [.RealType])
    }
  }
    
  public func asComplex(coerce coerce: Bool = false) throws -> Complex<Double> {
    if !coerce {
      switch self {
        case Flonum(let num):
          return Complex(num, 0.0)
        case Complexnum(let complex):
          return complex
        default:
          throw EvalError.TypeError(self, [.ComplexType])
      }
    }
    switch self.normalized {
      case Fixnum(let num):
        return Complex(Double(num), 0.0)
      case .Bignum(let num):
        return Complex(num.doubleValue, 0.0)
      case .Rat(let num):
        return Complex(Double(num.numerator) / Double(num.denominator), 0.0)
      case .Bigrat(let num):
        return Complex(num.numerator.doubleValue / num.denominator.doubleValue, 0.0)
      case .Flonum(let num):
        return Complex(num, 0.0)
      case .Complexnum(let num):
        return num
      default:
        throw EvalError.TypeError(self, [.ComplexType])
    }
  }
  
  public func asChar() throws -> UniChar {
    guard case Char(let res) = self else {
      throw EvalError.TypeError(self, [.CharType])
    }
    return res
  }
  
  public func asCharStr() throws -> String {
    guard case Char(let res) = self else {
      throw EvalError.TypeError(self, [.CharType])
    }
    return String(UnicodeScalar(res))
  }
  
  public func asStr() throws -> String {
    guard case Str(let res) = self else {
      throw EvalError.TypeError(self, [.StrType])
    }
    return res.value
  }
  
  public func asPair() throws -> (Expr, Expr) {
    guard case Pair(let res) = self else {
      throw EvalError.TypeError(self, [.PairType])
    }
    return res
  }
  
  public func asVector() throws -> Vector {
    guard case Vec(let res) = self else {
      throw EvalError.TypeError(self, [.VectorType])
    }
    return res
  }
  
  public func asSymbol() throws -> Symbol {
    guard let symid = self.toSymbol() else {
      throw EvalError.TypeError(self, [.SymbolType])
    }
    return symid
  }
  
  public func toSymbol() -> Symbol? {
    switch self {
      case Sym(let sym):
        return sym
      default:
        return nil
    }
  }
}


/// This extension makes `Expr` implement the `CustomStringConvertible`.
///
extension Expr: CustomStringConvertible {
  
  private static func escapeStr(str: String) -> String {
    var res = ""
    for c in str.characters {
      switch c {
        case "\u{7}":  res += "\\a"
        case "\u{8}":  res += "\\b"
        case "\t":     res += "\\t"
        case "\n":     res += "\\n"
        case "\u{11}": res += "\\v"
        case "\u{12}": res += "\\f"
        case "\r":     res += "\\r"
        case "\u{27}": res += "\\e"
        case "\"":     res += "\\\""
        case "\\":     res += "\\\\"
        default:       res.append(c)
      }
    }
    return res
  }
  
  public var description: String {
    var enclVectors = Set<Vector>()
    var vectorIdMap = [Vector: Int]()
    var enclVariables = Set<Variable>()
    
    func stringReprOf(expr: Expr) -> String {
      switch expr {
        case .Undef:
          return "#<undef>"
        case .Void:
          return "#<void>"
        case .Eof:
          return "#<eof>"
        case .Null:
          return "()"
        case .True:
          return "#t"
        case .False:
          return "#f"
        case .Sym(let sym):
          return sym.description
        case .Fixnum(let val):
          return String(val)
        case .Bignum(let val):
          return val.description
        case .Rat(let val):
          return val.description
        case .Bigrat(let val):
          return val.description
        case .Flonum(let val):
          if val.isInfinite {
            return val.isSignMinus ? "-inf.0" : "+inf.0"
          } else if val.isNaN {
            return "+nan.0"
          } else {
            return String(val)
          }
        case .Complexnum(let val):
          return val.description
        case .Char(let ch):
          switch ch {
            case   7: return "#\\alarm"
            case   8: return "#\\backspace"
            case 127: return "#\\delete"
            case  27: return "#\\escape"
            case  10: return "#\\newline"
            case   0: return "#\\null"
            case  12: return "#\\page"
            case  13: return "#\\return"
            case  32: return "#\\space"
            case   9: return "#\\tab"
            case  11: return "#\\vtab"
            default :
              if WHITESPACES_NL.characterIsMember(ch) ||
                 CONTROL_CHARS.characterIsMember(ch) ||
                 ILLEGAL_CHARS.characterIsMember(ch) ||
                 MODIFIER_CHARS.characterIsMember(ch) ||
                 ch > 0xd7ff {
                return "#\\u\(String(ch, radix:16))"
              } else {
                return "#\\\(Character(UnicodeScalar(ch)))"
              }
          }
        case .Str(let str):
          return "\"\(Expr.escapeStr(str.value))\""
        case .Pair(let head, let tail):
          var res = "(" + stringReprOf(head)
          var expr = tail
          while case .Pair(let car, let cdr) = expr {
            res += " "
            res += stringReprOf(car)
            expr = cdr
          }
          return res + (expr.isNull ? ")" : " . \(expr))")
        case .Vec(let vector):
          if let vectorId = vectorIdMap[vector] {
            return "#\(vectorId)#"
          } else if enclVectors.contains(vector) {
            vectorIdMap[vector] = vectorIdMap.count
            return "#\(vectorIdMap.count - 1)#"
          } else if vector.exprs.count == 0 {
            return "#()"
          }
          enclVectors.insert(vector)
          var res = ""
          var sep = "#("
          for expr in vector.exprs {
            res = res + sep + stringReprOf(expr)
            sep = " "
          }
          enclVectors.remove(vector)
          if let vectorId = vectorIdMap[vector] {
            return "#\(vectorId)=\(res))"
          } else {
            return res + ")"
          }
        case .Promise(let promise):
          return "#<promise \(String(promise.hashValue, radix: 16))>"
        case .Special(let special):
          return "#<special \(String(special.hashValue, radix: 16))>"
        case .Proc(let proc):
          return "#<procedure \(String(proc.hashValue, radix: 16))>"
        case .Var(let v):
          if enclVariables.contains(v) {
            return "#<variable \(String(v.hashValue, radix: 16))"
          } else {
            enclVariables.insert(v)
            let res = "#<variable \(String(v.hashValue, radix: 16)): \(stringReprOf(v.value))>"
            enclVariables.remove(v)
            return res
          }
        case .Error(let error):
          return error.description
      }
    }
    
    return stringReprOf(self)
  }
}

public func ==(lhs: Expr, rhs: Expr) -> Bool {
  return equalExpr(lhs, rhs)
}
