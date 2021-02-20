//
//  main.swift
//  ArrayOfSwift
//
//  Created by HarryPhone on 2021/2/20.
//

import Foundation

struct ArrayBuffer<T> {
    var storage: UnsafeMutablePointer<ContiguousArrayStorage<T>>
}

struct ContiguousArrayStorage<T> {
    var metadata: UnsafeMutableRawPointer
    var refCounts: UInt
    var count: UInt
    var capacityAndFlags: UInt
    
    func getCapacity() -> UInt {
        return capacityAndFlags &>> 1
    }
    
    mutating func getElement(index: Int) -> T {
        return withUnsafeMutablePointer(to: &self) {
            let pointer = UnsafeMutableRawPointer($0.advanced(by: 1)).assumingMemoryBound(to: T.self)
            return pointer.advanced(by: index).pointee
        }
    }
}


var num = [1, 2, 3]

func getArrayBuffer<T>(from array: Array<T>) -> ArrayBuffer<T> {
    return unsafeBitCast(array, to: ArrayBuffer<T>.self)
}
var buffer = getArrayBuffer(from: num)
let count = buffer.storage.pointee.count
print("数组个数: \(count)")

print("数组容量: \(buffer.storage.pointee.getCapacity())")

print("--------------------------------")

if count > 0 {
    for i in 0..<count {
        print("数组元素: \(buffer.storage.pointee.getElement(index: Int(i)))")
    }
}



