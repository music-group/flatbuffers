//
// Created by Martin O'Shea on 15/06/2018.
//

import Foundation

// Allow us to get any size int in little endian form swift Data
public extension Data {
    func getIntegerType<T: FixedWidthInteger>(uoffset: UOffset) -> T {
        return self.withUnsafeBytes{ (pointer: UnsafePointer<UInt8>) in
            var numberLocation = pointer.advanced(by: Int(uoffset))

            return {
                var number: T = 0
                for count in 0..<(T.bitWidth / UInt8.bitWidth)  {
                    number = (number << (count * 8)) | T(numberLocation.pointee)
                    numberLocation = numberLocation.advanced(by: 1)
                }

                return number
                }()
        }
    }
}

// Table is the base class for generated Flatbuffer tables. The contains instance varibles for retrieving data
public protocol Table {
    var data: Data { get set }
    var tablePosition: UOffset { get set }

    init(data: Data, tablePosition: UOffset)

    /**
     Look up a fields location by looking at a table's vtable.

     - parameter vtableElementIndex: the index of the element in the vtable
     - returns: Returns an offset into the table object, or `0` if the field is not present.
     */
    func offset(vtableElementIndex: UInt32) -> UOffset

    func getIntegerType<T: FixedWidthInteger>(uoffset: UOffset) -> T
}

// default implementation of Table
public extension Table {
    init(data: Data, tablePosition: UOffset) {
        self.init(data: data, tablePosition: tablePosition)
        self.data = data
        self.tablePosition = tablePosition
    }

    /**
     Look up a field in the vtable.

     - parameter vtableElementIndex: the index of the element in the vtable
     - returns: Returns an offset into the table object, or `0` if the field is not present.
     */
    func offset(vtableElementIndex: UInt32) -> UOffset {
        // Note: every table stores a reference to its vtable as its first element
        let vtable = tablePosition - data.getIntegerType(uoffset: tablePosition)
        return {
                if vtableElementIndex < data.getIntegerType(uoffset: vtable) {
                    return data.getIntegerType(uoffset: vtable + vtableElementIndex)
                }
                else {
                    return 0
                }
            }()
    }

    func getIntegerType<T: FixedWidthInteger>(uoffset: UOffset) -> T {
        return data.getIntegerType(uoffset: uoffset)
    }
}

