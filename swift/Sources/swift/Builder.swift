import Foundation

extension FixedWidthInteger {
    var littleEndianData: Data {
        get {
            var littleEndian = self.littleEndian
            return Data(bytes: &littleEndian, count: MemoryLayout.size(ofValue: self))
        }
    }
}

// Flatbuffer builder that is used by the Flatbuffer compiler to generate entities defined in user-defined schemas
class Builder {
    // Even though these type names are not the most `swifty` it makes them easy to reference back to the
    // flatbuffer documentation and other flatbuffer implementations
    typealias SOffset = Int32
    typealias UOffset = UInt32
    typealias VOffset = UInt16

    // flatbuffer constants, static to allow use as function parameter defaults but
    // we can not calculate them using bitWidth
    private static let Int32ByteSize: UInt8 = 4
    private static let SizeFieldByteSize: UInt8 = Int32ByteSize
    private static let SOffsetByteSize: UInt8 = Int32ByteSize
    private static let UOffsetByteSize: UInt8 = Int32ByteSize
    private static let VOffsetByteSize: UInt8 = 2
    private static let ShortByteSize: UInt8 = 2
    private static let ByteSize: UInt8 = 1
    private static let VtableMetadataFields: UInt8 = 2

    /**
        A wrapper around a Swift Data buffer that keeps track of varibles
        that need to change every time a change happens to the buffer, this does not include position of data in the
        buffer as this class is not conserned with that bookkeeping only the counting of what data is used
     */
    fileprivate struct Buffer {
        private var buffer: Data
        // The amount of the allocated data unused
         public private(set) var spaceRemaining: UInt32

        init(initialSize: UInt32 = 1024) {
            buffer = Data(count: Int(initialSize))
            spaceRemaining = UInt32(buffer.count)
        }

        mutating func writeData(data: Data) {
            spaceRemaining -= UInt32(data.count)
            buffer.replaceSubrange(getBufferRange(rangeLength: UInt32(data.count)), with: data)
        }

        /**
            This should only be used in cases where data has been assigned space and the written,
            however the data now needs to be changed.
         */
        mutating func writeDataAtLocation(subrange: Range<Data.Index>, data: Data) {
            buffer.replaceSubrange(subrange, with: data)
        }

        mutating func clear() {
            buffer.resetBytes(in: 0..<buffer.count)
            spaceRemaining = UInt32(buffer.count)
        }

         /**
            Increases the size of the backing and copies the old data towards the
            end of the new buffer (since we build the buffer backwards).

            It ensures underlying data byte count is less then uoffset_t.max.
            This is necessary as offsets would not reach the data in the newly allocated section

            - Parameter minimumExpansion:   the new buffer size is guaranteed to have at least this amount of free bytes
                                            unless it has hit its maximum size
         */
        mutating func increaseDataSize(minimumExpansion: UInt32 = 0) {
            let currentSize = UInt32(buffer.count)
            let newSize = { () -> UInt32 in
                var proposedSize = (currentSize * 2) > minimumExpansion ? currentSize * 2 : minimumExpansion * 2
                if proposedSize > UOffset.max {
                    proposedSize = UOffset.max
                    if proposedSize < currentSize + minimumExpansion {
                        fatalError("""
                            Size of flatbuffer stucture tried to grow larger than \(UOffset.max)
                            which is not supported by the current flatbuffers spec
                            """)
                    }
                }
                return proposedSize
            }()

            // Note: the count constructor creates an array of zeroed data
            var newData = Data(count: numericCast(newSize))

            // Copy over data from the old buffer
            let startIndex = newData.startIndex.advanced(by: newData.count - buffer.count)
            let dataCopydestination: Range<Data.Index> = startIndex..<(newData.endIndex + 1)
            newData.replaceSubrange(dataCopydestination, with: buffer)

            // Add the new space allocated to our existing space
            spaceRemaining += numericCast(newData.count - buffer.count)
            buffer = newData
        }

        // Calculate the current offset from the start of the buffer
        var currentOffset: UOffset {
            get {
                return UInt32(buffer.count) - spaceRemaining
            }
        }

        var count: UInt32 {
            get {
                return UInt32(buffer.count)
            }
        }

        /**
            Gets a range of the buffer starting from the current offset with the length specified
            It is assumed that the size of the element to go into the range has been prepared
            i.e. prep function called and spacing remaining deceremented

            - Parameter rangeLength: the length of the range to be returned
         */
        func getBufferRange(rangeLength: UInt32) -> Range<Data.Index> {
            return buffer.startIndex.advanced(by:
                Int(currentOffset))..<buffer.startIndex.advanced(by: Int(currentOffset + rangeLength + 1)
            )
        }

        /**
            Use only when you need a range to data that have already been written into the buffer
         */
        func getBufferRange(location: UInt32, rangeLength: UInt32) -> Range<Data.Index> {
            return buffer.startIndex.advanced(by:
                Int(currentOffset))..<buffer.startIndex.advanced(by: Int(currentOffset + rangeLength + 1)
            )
        }
    }

    private var buffer: Buffer
    private var nested = false
    private var finished = false

    private var objectEnd: UOffset = 0
    private lazy var vTable = [UOffset](repeating: 0, count: 16)
    private var vTables = [UOffset]()
    private var vectorElementAmount: UInt32 = 0

    private var minAlign: UInt8 = 1

    /**
     Start builder with an initial size for the underlying data that will grow as required.

     - Parameter initialSize: the number of bytes allocated initially for building the buffer, default 1KiB
    */
    init(initialSize: UInt32 = 1024) {
        // buffer = Data(count: initialSize)
        buffer = Buffer(initialSize: initialSize)
        clear()
    }

    /**
         Reset the FlatBufferBuilder by purging all data that it holds.
    */
    public func clear() {
        // Clear data
        buffer.clear()

        // Clear bookkeeping
        nested = false
        finished = false
        objectEnd = 0
        vTables = [UOffset]()
        vectorElementAmount = 0
    }

    /**
        Add zero value bytes to prepare a new entry to be added.

        - Parameter byte_size: Number of bytes to add.
     */
    private func pad(byteSize: UInt32) {
        buffer.writeData(data: Data(count: numericCast(byteSize)))
    }

    /**
        Prepare to write an element of `size` after `additional_bytes`
        have been written, e.g. if you write a string, you need to align such
        that the int length field is aligned to `UOffset`, and
        the string data follows it directly.  If all you need to do is alignment, `additional_bytes`
        will be 0.

        - Parameter size: This is the of the new element to write.
        - Parameter additional_bytes: The padding size.
     */
    private func prep(size: UInt8, additional_bytes: UInt32 = 0) {
        // Track the biggest element we've ever aligned to.
        if size > minAlign {
            minAlign = size
        }

        // Find the amount of alignment needed such that `size` is properly
        // aligned after `additional_bytes`
        let preAlignSize = (~(UInt32(buffer.count) - buffer.spaceRemaining + additional_bytes)) + 1
        let alignSize = preAlignSize & UInt32(size - 1)

        // Reallocate the buffer if needed.
        let miniumAboutOfSpaceRequired: UInt32 = alignSize + numericCast(size) + additional_bytes
        if (buffer.spaceRemaining < miniumAboutOfSpaceRequired) {
            buffer.increaseDataSize(minimumExpansion: miniumAboutOfSpaceRequired - buffer.spaceRemaining)
        }
        pad(byteSize: alignSize);
    }

    /**
        Add `SOffset` at the `currentOffset`
        This function assumes the empty data exists for the `SOffset`

        - Parameter number: the SOffset number to be stored
     */
    private func addSOffset(_ number: SOffset) {
        buffer.writeData(data: number.littleEndianData)
    }

    /**
         Add `UOffset` at the currentOffset
         This function assumes the empty data exists for the `UOffset`

         - Parameter number: the SOffset number to be stored
     */
    private func addUOffset(_ number: UOffset) {
        buffer.writeData(data: number.littleEndianData)
    }

    private func addVOffset(_ number: VOffset) {
        prep(size: UInt8(Builder.ShortByteSize), additional_bytes: 0)
        addInternalShort(number)
    }

    /**
        Add a `short` to the buffer, properly aligned, and grows the buffer (if necessary).

        - Parameter number: A `short` into the buffer.
     */
    private func addInternalShort(_ number: UInt16) {
        buffer.writeData(data: number.littleEndianData)
    }

    /**
        Required at the end of all Strings and vectors
     */
    private func addNullTerimator() {
        buffer.writeData(data: Data(count: 1))
    }

    /**
        Finalizes the buffer, pointing to the given `rootTable`
        - Parameter rootTable: the offset of the main table in the buffer
     */
    public func finish(rootTable: UOffset) {
        assertNotNested()
        prep(size: minAlign, additional_bytes: UInt32(Builder.SOffsetByteSize))
        addUOffset(rootTable)
        finished = true;
    }

    private func assertNotNested() {
        if nested {
            fatalError("""
                         If you hit this fatalError, you're trying to construct a Table/Vector/String
                         during the construction of its parent table (between the MyTableBuilder
                         and builder.Finish()).
                         Move the creation of these sub-objects to above the MyTableBuilder to
                         not get this assert.
                         Ignoring this assert may appear to work in simple cases, but the reason
                         it is here is that storing objects in-line may cause vtable offsets
                         to not fit anymore. It also leads to vtable duplication.
                        """)
        }
    }

    private func assertNested() {
        if !nested {
            fatalError("""
                        If you get this fatalError, you're in an object while trying to write
                        data that belongs outside of an object.
                        To fix this, write non-inline data (like vectors) before creating
                        objects.
                        """)
        }
    }

    private func assertFinished() {
        if !finished {
            fatalError("""
                        If you get this fatalError, you're attempting to get access a buffer
                        which hasn't been finished yet. Be sure to call builder.Finish()
                        with your root table.
                        """)
        }
    }
}

// Vector code extension
typealias VectorBuilderMethods = Builder
extension VectorBuilderMethods {
    /**
        initializes bookkeeping for writing a new vector.
        - Parameter elementTypeSize: The size of an elemenet in bytes
        - Pamameter elememtCount: The number of elements that will be in the vector
        - Parameter alignment: The alignment of the vector, the default is the byte size of an `UOffset`
     */
    public func startVector(elementTypeSize: UInt32,
                            elememtCount: UInt32,
                            alignment: UInt8 = UInt8(UOffsetByteSize)) {
        assertNotNested()
        vectorElementAmount = elememtCount

        let totalByteSizeOfVector = (elementTypeSize * vectorElementAmount) +
                                    UInt32(Builder.SizeFieldByteSize) +
                                    UInt32(Builder.ByteSize)
        prep(size: alignment, additional_bytes: totalByteSizeOfVector)

        // Add null tereminator first as we are building vector backwards
        addNullTerimator()

        nested = true;
    }

    /**
        Writes data necessary to finish vector construction.
     */
    public func endVector() -> UOffset {
        // Note we should have already ensured we have enough memory for any writing that needs to be done here
        assertNested()

        assert(vectorElementAmount > 0)
        // prepend vector we its size in a 32bit number
        addUOffset(vectorElementAmount)

        nested = false
        return buffer.currentOffset
    }

    // CreateByteVector writes a ubyte vector
    func createByteVector(data: Data) -> UOffset {
        assertNotNested()
        nested = true

        startVector(elementTypeSize: UInt32(Builder.ByteSize),
                    elememtCount: UInt32(data.count),
                    alignment: Builder.ByteSize)

        buffer.writeData(data: data)

        return endVector()
    }
}

// Object builder code extension
typealias ObjectBuilderMethods = Builder
extension ObjectBuilderMethods {

    /**
        initializes bookkeeping for writing a new object.
        - Parameter feildCount: about of feilds to be stored in the object
     */
    public func startObject(feildCount: UInt32) {
        assertNotNested()

        if feildCount > vTable.count {
            // Old vTable too small make a new one
            vTable = [UOffset](repeating: 0, count: Int(feildCount))
        }

        else {
            // reuse old vTable
            vTable.removeAll(keepingCapacity: true)
        }

        nested = true
        objectEnd = buffer.currentOffset
    }

    /**
        writes data necessary to finish object construction.
    */
    public func endObject() -> UOffset {
        guard nested else {
            fatalError("FlatBuffers: endObject called without startObject")
        }

        return  writeVTable()
    }

    // Slot sets the vtable key `voffset` to the current location in the buffer.
    private func slot(slotnum: UInt32) {
        vTable[Int(slotnum)] = buffer.currentOffset
    }

    /**
        WriteVtable serializes the vtable for the current object, if applicable.

        A vtable has the following format:
            <VOffsetT:  size of the vtable in bytes, including this value>
            <VOffsetT:  size of the object in bytes, including the vtable offset>
            <VOffsetT:  offset for a field> * N, where N is the number of fields in
                        the schema for this type. Includes deprecated fields.
        Thus, a vtable is made of 2 + N elements, each SizeVOffsetT bytes wide.

        An object has the following format:
            <SOffsetT: offset to this object's vtable (may be negative)>
            <byte: data>+

        TODO:   Before writing out the vtable, this should check pre-existing vtables for equality
                to this one. If an equal vtable is found, point the object to the existing
                vtable and return. Because vtable values are sensitive to alignment of object data, not all
                logically-equal vtables will be deduplicated.
     */
    private func writeVTable() -> UOffset {
        // Prepend a zero scalar to the object. Later in this function we'll
        // write an offset here that points to the object's vtable:
        addSOffset(0)
        let objectOffset = buffer.currentOffset

        // Check how much data we actually have in the vtable
        let dataLength = { () -> UInt32 in
            var index = vTable.count - 1
            while vTable[index] == 0 && index >= 0 {
                index -= 1
            }
            return UInt32(index + 1)
        }()

        //TODO: Add the ability to reuse pre-existing vtables

        // Write memory locations in vTable to buffer
        for index in stride(from: objectOffset, to: objectOffset - (dataLength - 1), by: -1) {
            let offset: VOffset = vTable[Int(index)] != 0 ? VOffset(buffer.currentOffset - vTable[Int(index)]) : 0
            addVOffset(offset)
        }

        // The two metadata fields are written last.

        // First, store the object bytesize:
        let objectSize = objectOffset - objectEnd
        addVOffset(VOffset(objectSize))

        // Second, store the vtable bytesize:
        addVOffset(VOffset(dataLength + UInt32(Builder.VtableMetadataFields) * UInt32(Builder.VOffsetByteSize)))

        // Next, write the offset to the new vtable in the
        // already-allocated SOffsetT at the beginning of this object:
        // Note this value is subtracted not added in the standard
        buffer.writeDataAtLocation(subrange: buffer.getBufferRange(location: objectOffset,
                                                                   rangeLength: UInt32(Builder.SOffsetByteSize)),
                                   data: SOffset(buffer.currentOffset - objectOffset).littleEndianData)

        // Finally, store this vtable in memory for future
        vTables.append(buffer.currentOffset)

        nested = false
        return objectOffset
    }
}

// String related methods
typealias StringBuilderMethods = Builder
extension StringBuilderMethods {
    /**
        Add string to buffer

        - Parameter string: A swift string with only ASCII valid charactors
     */
    func createString(string: String) -> UOffset {
        guard let stringData = string.data(using: .ascii) else {
            fatalError("Tried to convert a string that contained non ascii charactor")
        }

        startVector(elementTypeSize: 1, elememtCount: UInt32(string.count), alignment: 1)

        buffer.writeData(data: stringData)

        return endVector()
    }
}

// Buffer data setting helpers
typealias BuilderHelpers = Builder
extension BuilderHelpers {

    /**
        Add a struct to the table. Structs are stored inline, so nothing additional is being added.

        - Parameter voffset: The index into the vtable.
        - Parameter structOffset: The offset of the created struct.
        - Parameter defaultOffset: The default value is always `0`.
     */
    public func addStruct(voffset: VOffset, structOffset: UOffset, defaultOffset: UOffset) {
        if(structOffset != defaultOffset) {
            structAtCurrentOffset(structOffset);
            slot(slotnum: UInt32(voffset));
        }
    }

    /**
        Ensure a structure is stored inline in object

        - Parameter structOffset: The offset of the struct.
     */
    private func structAtCurrentOffset(_ structOffset: UOffset) {
        if structOffset != buffer.currentOffset {
            fatalError("""
                        FlatBuffers: struct must be serialized inline.

                        Structures are always stored inline, they need to be created right
                        where they're used.  You'll get this fatalError if you
                        created it elsewhere.
                        """)
        }
    }

    /**
        Adds data to the current object being constructed
     */
    private func addObjectElement(vTableIndex: UInt32, data: Data, dataElementWidth: UInt8) {
        prep(size: dataElementWidth, additional_bytes: 0)
        buffer.writeData(data: data)
        slot(slotnum: vTableIndex)
    }

    /**
        Add any `FixedWidthInteger` to a table at `vTableIndex`

        - Parameter vTableIndex: The index into the vtable.
        - Parameter value:  A `Bool` to put into the buffer, compare `value` against the default value `defaultValue`.
                            If `value` contains the `defaultValue`, it can be skipped.
        - Parameter defaultValue: A `Bool` default value to compare against.
     */
    public func addIntegerType<T: FixedWidthInteger>(vTableIndex: UInt32, value: T, defaultValue: T) {
        if value != defaultValue {
            addObjectElement(vTableIndex: vTableIndex,
                             data: value.littleEndianData,
                             dataElementWidth: UInt8(value.bitWidth / UInt8.bitWidth))
        }
    }

    /**
        Add a `Bool` to a table at `vTableIndex`

        - Parameter vTableIndex: The index into the vtable.
        - Parameter value:  A `Bool` to put into the buffer, compare `value` against the default value `defaultValue`.
                            If `value` contains the `defaultValue`, it can be skipped.
        - Parameter defaultValue: A `Bool` default value to compare against.
     */
    public func addBoolean(vTableIndex: UInt32, value: Bool, defaultValue: Bool) {
            addIntegerType(vTableIndex: vTableIndex,  value: value ? 1 : 0, defaultValue: defaultValue ? 1: 0)
    }

    /**
        Add a `Float` to a table at `vTableIndex`

        - Parameter vTableIndex: The index into the vtable.
        - Parameter value:  A `Float` to put into the buffer, compare `value` against the default value `defaultValue`.
                            If `value` contains the `defaultValue`, it can be skipped.
        - Parameter defaultValue: A `Float` default value to compare against.
     */
    public func addFloat(vTableIndex: UInt32, value: Float, defaultValue: Float) {
        if value != defaultValue {
            addObjectElement(vTableIndex: vTableIndex,
                             data: value.bitPattern.littleEndianData,
                             dataElementWidth: UInt8(value.bitPattern.bitWidth / UInt8.bitWidth))
        }
    }

    /**
        Add a `Double` to a table at `vTableIndex`

        - Parameter vTableIndex: The index into the vtable.
        - Parameter value:  A `Double` to put into the buffer, compare `value` against the default value `defaultValue`.
                            If `value` contains the `defaultValue`, it can be skipped.
        - Parameter defaultValue: A `Double` default value to compare against.
     */
    public func addDouble(vTableIndex: UInt32, value: Double, defaultValue: Double) {
        if value != defaultValue {
            addObjectElement(vTableIndex: vTableIndex,
                             data: value.bitPattern.littleEndianData,
                             dataElementWidth: UInt8(value.bitPattern.bitWidth / UInt8.bitWidth))
        }
    }
}
