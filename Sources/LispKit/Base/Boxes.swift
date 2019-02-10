//
//  Boxes.swift
//  LispKit
//
//  Created by Matthias Zenger on 03/02/2016.
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

///
/// Generic box for value and reference types.
///
public final class ImmutableBox<T>: Reference {
  public let value: T

  public init(_ value: T) {
    self.value = value
  }
}

///
/// Generic mutable box for value and reference types.
///
public final class MutableBox<T>: Reference {
  public var value: T

  public init(_ value: T) {
    self.value = value
  }
}

///
/// Generic weak, mutable box for reference types.
///
public final class WeakBox<T: AnyObject>: Reference {
  public weak var value: T?

  public init(_ value: T?) {
    self.value = value
  }
}
