//
//  Equality.swift
//  LispKit
//
//  Created by Matthias Zenger on 30/01/2016.
//  Copyright © 2016-2019 ObjectHub. All rights reserved.
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

import Foundation
import NumberKit


//-------- MARK: - Equals

struct Equality: Hashable {
  let ref1: Reference
  let ref2: Reference

  init(_ ref1: Reference, _ ref2: Reference) {
    self.ref1 = ref1
    self.ref2 = ref2
  }

  func hash(into hasher: inout Hasher) {
    let value: Int = ObjectIdentifier(ref1).hashValue ^ ObjectIdentifier(ref2).hashValue
    hasher.combine(value)
  }

  static func ==(lhs: Equality, rhs: Equality) -> Bool {
    return lhs.ref1 == rhs.ref1 && lhs.ref2 == rhs.ref2 ||
           lhs.ref1 == rhs.ref2 && lhs.ref2 == rhs.ref1
  }
}

public func equalExpr(_ this: Expr, _ that: Expr) -> Bool {
  var equalities = Set<Equality>()

  func equals(_ lhs: Expr, _ rhs: Expr) -> Bool {
    switch (lhs.normalized, rhs.normalized) {
      case (.undef, .undef),
           (.void, .void),
           (.eof, .eof),
           (.null, .null),
           (.true, .true),
           (.false, .false):
        return true
      case (.uninit(let sym1), .uninit(let sym2)):
        return sym1 === sym2
      case (.symbol(let sym1), .symbol(let sym2)):
        return sym1 === sym2
      case (.fixnum(let num1), .fixnum(let num2)):
        return num1 == num2
      case (.bignum(let num1), .bignum(let num2)):
        return num1 == num2
      case (.rational(let n1, let d1), .rational(let n2, let d2)):
        return equals(n1, n2) && equals(d1, d2)
      case (.flonum(let num1), .flonum(let num2)):
        return num1 == num2 && num1.sign == num2.sign
      case (.complex(let num1), .complex(let num2)):
        return num1.value == num2.value &&
               num1.value.re.sign == num2.value.re.sign &&
               num1.value.im.sign == num2.value.im.sign
      case (.char(let ch1), .char(let ch2)):
        return ch1 == ch2
      case (.string(let str1), .string(let str2)):
        return str1 == str2
      case (.bytes(let bvector1), .bytes(let bvector2)):
        guard bvector1.value.count == bvector2.value.count else {
          return false
        }
        for i in bvector1.value.indices {
          guard bvector1.value[i] == bvector2.value[i] else {
            return false
          }
        }
        return true
      case (.pair(let car1, let cdr1), .pair(let car2, let cdr2)):
        return equals(car1, car2) && equals(cdr1, cdr2)
      case (.box(let cell1), .box(let cell2)):
        guard cell1 !== cell2 else {
          return true
        }
        let equality = Equality(cell1, cell2)
        guard !equalities.contains(equality) else {
          return true
        }
        equalities.insert(equality)
        return equals(cell1.value, cell2.value)
      case (.mpair(let tuple1), .mpair(let tuple2)):
        guard tuple1 !== tuple2 else {
          return true
        }
        let equality = Equality(tuple1, tuple2)
        guard !equalities.contains(equality) else {
          return true
        }
        equalities.insert(equality)
        return equals(tuple1.fst, tuple2.fst) && equals(tuple1.snd, tuple2.snd)
      case (.array(let array1), .array(let array2)):
        guard array1 !== array2 else {
          return true
        }
        let equality = Equality(array1, array2)
        guard !equalities.contains(equality) else {
          return true
        }
        guard array1.exprs.count == array2.exprs.count else {
          return false
        }
        equalities.insert(equality)
        for i in array1.exprs.indices {
          guard equals(array1.exprs[i], array2.exprs[i]) else {
            return false
          }
        }
        return true
      case (.vector(let vector1), .vector(let vector2)):
        guard vector1 !== vector2 else {
          return true
        }
        guard vector1.isGrowableVector == vector2.isGrowableVector else {
          return false
        }
        let equality = Equality(vector1, vector2)
        guard !equalities.contains(equality) else {
          return true
        }
        guard vector1.exprs.count == vector2.exprs.count else {
          return false
        }
        equalities.insert(equality)
        for i in vector1.exprs.indices {
          guard equals(vector1.exprs[i], vector2.exprs[i]) else {
            return false
          }
        }
        return true
      case (.record(let record1), .record(let record2)):
        guard record1 !== record2 else {
          return true
        }
        let equality = Equality(record1, record2)
        guard !equalities.contains(equality) else {
          return true
        }
        guard record1.sameKindAs(record2) && record1.exprs.count == record2.exprs.count else {
          return false
        }
        equalities.insert(equality)
        for i in record1.exprs.indices {
          guard equals(record1.exprs[i], record2.exprs[i]) else {
            return false
          }
        }
        return true
      case (.table(let map1), .table(let map2)):
        // Identical maps are also equals
        guard map1 !== map2 else {
          return true
        }
        // Maps with incompatible hashing and equality functions are not equals
        switch (map1.equiv, map2.equiv) {
          case (.eq, .eq), (.eqv, .eqv), (.equal, .equal):
            break;
          case (.custom(let procs1), .custom(let procs2)):
            guard procs1.eql == procs2.eql && procs1.hsh == procs2.hsh else {
              return false
            }
          default:
            return false
        }
        // Assume equality (to handle recursive dependencies)
        let equality = Equality(map1, map2)
        guard !equalities.contains(equality) else {
          return true
        }
        equalities.insert(equality)
        // Check for structural equality of all mappings
        // TODO: Consider optimizing this; the algorithm currently has complexity O(n*n)
        let mappings1 = map1.mappings
        var count2 = 0
        var checkpointEqualities = equalities
        outer:
        for (key2, value2) in map2.mappings {
          count2 += 1
          for (key1, value1) in mappings1 {
            if equals(key1, key2) && equals(value1, value2) {
              checkpointEqualities = equalities
              continue outer
            } else {
              equalities = checkpointEqualities
            }
          }
          return false
        }
        return count2 == mappings1.count
      case (.promise(let promise1), .promise(let promise2)):
        return promise1 == promise2
      case (.values(let e1), .values(let e2)):
        return equals(e1, e2)
      case (.procedure(let e1), .procedure(let e2)):
        return e1 == e2
      case (.special(let e1), .special(let e2)):
        return e1 == e2
      case (.env(let e1), .env(let e2)):
        return e1 == e2
      case (.port(let p1), .port(let p2)):
        return p1 == p2
      case (.object(let o1), .object(let o2)):
        return o1 == o2
      case (.tagged(let t1, let e1), .tagged(let t2, let e2)):
        return eqvExpr(t1, t2) && equals(e1, e2)
      case (.error(let e1), .error(let e2)):
        return e1 == e2
      case (.syntax(let p1, let e1), .syntax(let p2, let e2)):
        return p1 == p2 && equals(e1, e2)
      default:
        return false
    }
  }

  return equals(this, that)
}


//-------- MARK: - Eqv

public func eqvExpr(_ lhs: Expr, _ rhs: Expr) -> Bool {
  switch (lhs.normalized, rhs.normalized) {
    case (.undef, .undef),
         (.void, .void),
         (.eof, .eof),
         (.null, .null),
         (.true, .true),
         (.false, .false):
      return true
    case (.uninit(let sym1), .uninit(let sym2)):
      return sym1 === sym2
    case (.symbol(let sym1), .symbol(let sym2)):
      return sym1 === sym2
    case (.fixnum(let num1), .fixnum(let num2)):
      return num1 == num2
    case (.bignum(let num1), .bignum(let num2)):
      return num1 == num2
    case (.rational(let n1, let d1), .rational(let n2, let d2)):
      return eqvExpr(n1, n2) && eqvExpr(d1, d2)
    case (.flonum(let num1), .flonum(let num2)):
      return num1 == num2 && num1.sign == num2.sign
    case (.complex(let num1), .complex(let num2)):
      return num1.value == num2.value &&
             num1.value.re.sign == num2.value.re.sign &&
             num1.value.im.sign == num2.value.im.sign
    case (.char(let ch1), .char(let ch2)):
      return ch1 == ch2
    case (.string(let str1), .string(let str2)):
      return str1 === str2
    case (.bytes(let bvector1), .bytes(let bvector2)):
      return bvector1 === bvector2
    case (.pair(let car1, let cdr1), .pair(let car2, let cdr2)):
      return eqvExpr(car1, car2) && eqvExpr(cdr1, cdr2)
    case (.box(let c1), .box(let c2)):
      return c1 === c2
    case (.mpair(let t1), .mpair(let t2)):
      return t1 === t2
    case (.array(let array1), .array(let array2)):
      return array1 === array2
    case (.vector(let vector1), .vector(let vector2)):
      return vector1 === vector2
    case (.record(let record1), .record(let record2)):
      return record1 === record2
    case (.table(let map1), .table(let map2)):
      return map1 === map2
    case (.promise(let promise1), .promise(let promise2)):
      return promise1 === promise2
    case (.values(let e1), .values(let e2)):
      return eqvExpr(e1, e2)
    case (.procedure(let e1), .procedure(let e2)):
      return e1 === e2
    case (.special(let e1), .special(let e2)):
      return e1 === e2
    case (.env(let e1), .env(let e2)):
      return e1 === e2
    case (.port(let p1), .port(let p2)):
      return p1 === p2
    case (.object(let o1), .object(let o2)):
      return o1 === o2
    case (.tagged(let t1, let e1), .tagged(let t2, let e2)):
      return eqvExpr(t1, t2) && eqvExpr(e1, e2)
    case (.error(let e1), .error(let e2)):
      return e1 === e2
    case (.syntax(let p1, let e1), .syntax(let p2, let e2)):
      return p1 == p2 && eqvExpr(e1, e2)
    default:
      return false
  }
}


//-------- MARK: - Eq

public func eqExpr(_ lhs: Expr, _ rhs: Expr) -> Bool {
  switch (lhs, rhs) {
    case (.undef, .undef),
         (.void, .void),
         (.eof, .eof),
         (.null, .null),
         (.true, .true),
         (.false, .false):
      return true
    case (.uninit(let sym1), .uninit(let sym2)):
      return sym1 === sym2
    case (.symbol(let sym1), .symbol(let sym2)):
      return sym1 === sym2
    case (.fixnum(let num1), .fixnum(let num2)):
      return num1 == num2
    case (.bignum(let num1), .bignum(let num2)):
      return num1 == num2
    case (.rational(let n1, let d1), .rational(let n2, let d2)):
      return eqExpr(n1, n2) && eqExpr(d1, d2)
    case (.flonum(let num1), .flonum(let num2)):
      return num1 == num2 && num1.sign == num2.sign
    case (.complex(let num1), .complex(let num2)):
      return num1.value == num2.value &&
             num1.value.re.sign == num2.value.re.sign &&
             num1.value.im.sign == num2.value.im.sign
    case (.char(let ch1), .char(let ch2)):
      return ch1 == ch2
    case (.string(let str1), .string(let str2)):
      return str1 === str2
    case (.bytes(let bvector1), .bytes(let bvector2)):
      return bvector1 === bvector2
    case (.pair(let car1, let cdr1), .pair(let car2, let cdr2)):
      return eqExpr(car1, car2) && eqExpr(cdr1, cdr2)
    case (.box(let c1), .box(let c2)):
      return c1 === c2
    case (.mpair(let t1), .mpair(let t2)):
      return t1 === t2
    case (.array(let array1), .array(let array2)):
      return array1 === array2
    case (.vector(let vector1), .vector(let vector2)):
      return vector1 === vector2
    case (.record(let record1), .record(let record2)):
      return record1 === record2
    case (.table(let map1), .table(let map2)):
      return map1 === map2
    case (.promise(let promise1), .promise(let promise2)):
      return promise1 === promise2
    case (.values(let e1), .values(let e2)):
      return eqExpr(e1, e2)
    case (.procedure(let e1), .procedure(let e2)):
      return e1 === e2
    case (.special(let e1), .special(let e2)):
      return e1 === e2
    case (.env(let e1), .env(let e2)):
      return e1 === e2
    case (.port(let p1), .port(let p2)):
      return p1 === p2
    case (.object(let o1), .object(let o2)):
      return o1 === o2
    case (.tagged(let t1, let e1), .tagged(let t2, let e2)):
      return eqvExpr(t1, t2) && eqExpr(e1, e2)
    case (.error(let e1), .error(let e2)):
      return e1 === e2
    case (.syntax(let p1, let e1), .syntax(let p2, let e2)):
      return p1 == p2 && eqExpr(e1, e2)
    default:
      return false
  }
}


//-------- MARK: - Numeric comparisons

enum NumberPair {
  case fixnumPair(Int64, Int64)
  case bignumPair(BigInt, BigInt)
  case rationalPair(Rational<Int64>, Rational<Int64>)
  case bigRationalPair(Rational<BigInt>, Rational<BigInt>)
  case flonumPair(Double, Double)
  case complexPair(Complex<Double>, Complex<Double>)

  init(_ fst: Expr, _ snd: Expr) throws {
    guard let res = NumberPair(fst, and: snd) else {
      try snd.assertType(.numberType)
      try fst.assertType(.numberType)
      preconditionFailure()
    }
    self = res
  }

  init?(_ fst: Expr, and snd: Expr) {
    switch (fst, snd) {
      case (.fixnum(let lhs), .fixnum(let rhs)):
        self = .fixnumPair(lhs, rhs)
      case (.fixnum(let lhs), .bignum(let rhs)):
        self = .bignumPair(BigInt(lhs), rhs)
      case (.fixnum(let lhs), .rational(.fixnum(let n), .fixnum(let d))):
        self = .rationalPair(Rational(lhs), Rational(n, d))
      case (.fixnum(let lhs), .rational(.bignum(let n), .bignum(let d))):
        self = .bigRationalPair(Rational(BigInt(lhs)), Rational(n, d))
      case (.fixnum(let lhs), .flonum(let rhs)):
        self = .flonumPair(Double(lhs), rhs)
      case (.fixnum(let lhs), .complex(let rhs)):
        self = .complexPair(Complex(Double(lhs)), rhs.value)
      case (.bignum(let lhs), .fixnum(let rhs)):
        self = .bignumPair(lhs, BigInt(rhs))
      case (.bignum(let lhs), .bignum(let rhs)):
        self = .bignumPair(lhs, rhs)
      case (.bignum(let lhs), .rational(.fixnum(let n), .fixnum(let d))):
        self = .bigRationalPair(Rational(lhs), Rational(BigInt(n), BigInt(d)))
      case (.bignum(let lhs), .rational(.bignum(let n), .bignum(let d))):
        self = .bigRationalPair(Rational(lhs), Rational(n, d))
      case (.bignum(let lhs), .flonum(let rhs)):
        self = .flonumPair(lhs.doubleValue, rhs)
      case (.bignum(let lhs), .complex(let rhs)):
        self = .complexPair(Complex(lhs.doubleValue), rhs.value)
      case (.rational(.fixnum(let n), .fixnum(let d)), .fixnum(let rhs)):
        self = .rationalPair(Rational(n, d), Rational(rhs))
      case (.rational(.fixnum(let n), .fixnum(let d)), .bignum(let rhs)):
        self = .bigRationalPair(Rational(BigInt(n), BigInt(d)), Rational(rhs))
      case (.rational(.fixnum(let n1), .fixnum(let d1)),
            .rational(.fixnum(let n2), .fixnum(let d2))):
        self = .rationalPair(Rational(n1, d1), Rational(n2, d2))
      case (.rational(.fixnum(let n1), .fixnum(let d1)),
            .rational(.bignum(let n2), .bignum(let d2))):
        self = .bigRationalPair(Rational(BigInt(n1), BigInt(d1)), Rational(n2, d2))
      case (.rational(.fixnum(let n), .fixnum(let d)), .flonum(let rhs)):
        self = .flonumPair(Double(n) / Double(d), rhs)
      case (.rational(.fixnum(let n), .fixnum(let d)), .complex(let rhs)):
        self = .complexPair(Complex(Double(n) / Double(d)), rhs.value)
      case (.rational(.bignum(let n), .bignum(let d)), .fixnum(let rhs)):
        self = .bigRationalPair(Rational(n, d), Rational(BigInt(rhs)))
      case (.rational(.bignum(let n), .bignum(let d)), .bignum(let rhs)):
        self = .bigRationalPair(Rational(n, d), Rational(rhs))
      case (.rational(.bignum(let n1), .bignum(let d1)),
            .rational(.fixnum(let n2), .fixnum(let d2))):
        self = .bigRationalPair(Rational(n1, d1), Rational(BigInt(n2), BigInt(d2)))
      case (.rational(.bignum(let n1), .bignum(let d1)),
            .rational(.bignum(let n2), .bignum(let d2))):
        self = .bigRationalPair(Rational(n1, d1), Rational(n2, d2))
      case (.rational(.bignum(let n), .bignum(let d)), .flonum(let rhs)):
        self = .flonumPair(n.doubleValue / d.doubleValue, rhs)
      case (.rational(.bignum(let n), .bignum(let d)), .complex(let rhs)):
        self = .complexPair(Complex(n.doubleValue / d.doubleValue), rhs.value)
      case (.flonum(let lhs), .fixnum(let rhs)):
        self = .flonumPair(lhs, Double(rhs))
      case (.flonum(let lhs), .bignum(let rhs)):
        self = .flonumPair(lhs, rhs.doubleValue)
      case (.flonum(let lhs), .rational(.fixnum(let n), .fixnum(let d))):
        self = .flonumPair(lhs, Double(n) / Double(d))
      case (.flonum(let lhs), .rational(.bignum(let n), .bignum(let d))):
        self = .flonumPair(lhs, n.doubleValue / d.doubleValue)
      case (.flonum(let lhs), .flonum(let rhs)):
        self = .flonumPair(lhs, rhs)
      case (.flonum(let lhs), .complex(let rhs)):
        self = .complexPair(Complex(lhs), rhs.value)
      case (.complex(let lhs), .fixnum(let rhs)):
        self = .complexPair(lhs.value, Complex(Double(rhs)))
      case (.complex(let lhs), .bignum(let rhs)):
        self = .complexPair(lhs.value, Complex(rhs.doubleValue))
      case (.complex(let lhs), .rational(.fixnum(let n), .fixnum(let d))):
        self = .complexPair(lhs.value, Complex(Double(n) / Double(d)))
      case (.complex(let lhs), .rational(.bignum(let n), .bignum(let d))):
        self = .complexPair(lhs.value, Complex(n.doubleValue / d.doubleValue))
      case (.complex(let lhs), .flonum(let rhs)):
        self = .complexPair(lhs.value, Complex(rhs))
      case (.complex(let lhs), .complex(let rhs)):
        self = .complexPair(lhs.value, rhs.value)
      default:
        return nil
    }
  }
}

public func compareNumber(_ lhs: Expr, with rhs: Expr) throws -> Int {
  guard let res = compare(lhs, with: rhs) else {
    try lhs.assertType(.realType)
    try rhs.assertType(.realType)
    preconditionFailure()
  }
  return res
}

public func compare(_ lhs: Expr, with rhs: Expr) -> Int? {
  guard let pair = NumberPair(lhs, and: rhs) else {
    return nil
  }
  switch pair {
    case .fixnumPair(let lnum, let rnum):
      return lnum < rnum ? -1 : (lnum > rnum ? 1 : 0)
    case .bignumPair(let lnum, let rnum):
      return lnum < rnum ? -1 : (lnum > rnum ? 1 : 0)
    case .rationalPair(let lnum, let rnum):
      return lnum < rnum ? -1 : (lnum > rnum ? 1 : 0)
    case .bigRationalPair(let lnum, let rnum):
      return lnum < rnum ? -1 : (lnum > rnum ? 1 : 0)
    case .flonumPair(let lnum, let rnum):
      return lnum < rnum ? -1 : (lnum > rnum ? 1 : 0)
    default:
      return nil
  }
}
