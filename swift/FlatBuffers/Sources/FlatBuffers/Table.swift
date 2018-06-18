//
// Created by Martin O'Shea on 15/06/2018.
//

import Foundation

extension Data {
    func getIntegerType<T>(uoffset: UOffset) -> T where T: FixedWidthInteger {
        return self.withUnsafeBytes{ (pointer: UnsafePointer<UInt8>) in
            var numberLocation = pointer.advanced(by: Int(uoffset))

            let numberToReturn: T = {
                var number: T = 0
                for count in 0..<4 {
                    number = (number << (count * 8)) | T(numberLocation.pointee)
                    numberLocation = numberLocation.advanced(by: 1)
                }

                return number
            }()

            return numberToReturn
        }
    }
}

// Table is the base class for generated Flatbuffer tables. The contains instance varibles for retrieving data
struct Table {
    private let data: Data
    private let tablePosition: UOffset

    init(data: Data, tablePosition: UOffset) {
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
}
