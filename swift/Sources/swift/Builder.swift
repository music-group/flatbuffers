import Foundation

extension UInt32 {
    var littleEndianData: Data {
        get {
            var littleEndian = self.littleEndian
            return Data(bytes: &littleEndian, count: MemoryLayout.size(ofValue: self))
        }
    }
}

class Builder {
    typealias UOffset = UInt32

    private let sizeFieldByteSize: UInt32 = 4
    private let nullTerminatorByteSize: UInt32 = 1

    private var buffer: Data
    private var nested = false
    private var finished = false
    private var objectStart = 0
    private var vTablesEntriesAmount: UInt32 = 0
    private var vectorElementAmount: UInt32 = 0
    // The amount of the allocated data left to pack data into
    private var spaceRemaining: UOffset = 0
    private var minAlign: UInt8 = 1
    // calculate the current offset from the start of the buffer
    var currentOffset: UOffset {
        get {
            return UInt32(buffer.count) - spaceRemaining
        }
    }

    /**
        Start builder with an initial size for the unlying data, that will grow as required.

        `initialSize` the amount of bytes allocated initially for building the buffer, default 1KiB
    */
    init(initialSize: Int = 1024) {
        buffer = Data(count: initialSize)
        clear()
    }

    /**
         Reset the FlatBufferBuilder by purging all data that it holds.
    */
    func clear() {
        buffer.resetBytes(in: 0..<buffer.count)
        nested = false
        finished = false
        objectStart = 0
        vTablesEntriesAmount = 0
        vectorElementAmount = 0
        spaceRemaining = 0
    }

    /**
        Increases the size of the backing and copies the old data towards the
        end of the new buffer (since we build the buffer backwards).

        It ensure underlying data byte count is less then uoffset_t.max.
        This is necessary as offsets would not reach the data in the new allocated section

        `minimumExpansion` the new buffer size is garenteed to have at least this amount of free bytes
        unless it has hit its maximum size
    */
    private func increaseDataSize(minimumExpansion: UInt32 = 0) {
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

        // Copy over data from old buffer
        let startIndex = newData.startIndex.advanced(by: newData.count - buffer.count)
        // FIXME: I don't think this includes the last need byte
        let dataCopydestination: Range<Data.Index> = startIndex..<newData.endIndex
        newData.replaceSubrange(dataCopydestination, with: buffer)

        // add the new space allocated to our existing space
        spaceRemaining += numericCast(newData.count - buffer.count)
        buffer = newData
    }

    /**
     * Add zero valued bytes to prepare a new entry to be added.
     *
     * @param byte_size Number of bytes to add.
     */
    private func pad(byteSize: UInt32) {
        spaceRemaining -= byteSize
        let dataCopydestination: Range<Data.Index> = numericCast(spaceRemaining)..<numericCast(spaceRemaining+byteSize)

        buffer.replaceSubrange(dataCopydestination, with: Data(count: numericCast(byteSize)))
    }

    /**
     * Prepare to write an element of `size` after `additional_bytes`
     * have been written, e.g. if you write a string, you need to align such
     * the int length field is aligned to {@link com.google.flatbuffers.Constants#SIZEOF_INT}, and
     * the string data follows it directly.  If all you need to do is alignment, `additional_bytes`
     * will be 0.
     *
     * @param size This is the of the new element to write.
     * @param additional_bytes The padding size.
     */
    private func prep(size: UInt8, additional_bytes: UInt32) {
        // Track the biggest thing we've ever aligned to.
        if size > minAlign {
            minAlign = size
        }

        // Find the amount of alignment needed such that `size` is properly
        // aligned after `additional_bytes`
        let preAlignSize = (~(UInt32(buffer.count) - spaceRemaining + additional_bytes)) + 1
        let alignSize = preAlignSize & UInt32(size - 1)
        // Reallocate the buffer if needed.

        let miniumAboutOfSpaceRequired: UInt32 = alignSize + numericCast(size) + additional_bytes
        if (spaceRemaining < miniumAboutOfSpaceRequired) {
            increaseDataSize(minimumExpansion: miniumAboutOfSpaceRequired - spaceRemaining)
        }
        pad(byteSize: alignSize);
    }

    public func startVector(elementTypeSize: UInt32,
                            elememtCount: UInt32,
                            alignment: UInt8 = UInt8(UInt32.bitWidth / UInt8.bitWidth)) {
        assertNotNested()
        vectorElementAmount = elememtCount

        let totalByteSizeOfVector = (elementTypeSize * vectorElementAmount) + sizeFieldByteSize + nullTerminatorByteSize
        prep(size: alignment, additional_bytes: totalByteSizeOfVector)

        // Add null terminator
        addNullTerimator()

        nested = true;
    }

    public func endVector() -> UOffset {
        // Note we should have already ensured we have enough memory for any writing that needs to be done here
        assertNested()

        assert(vectorElementAmount > 0)
        // prepend vector we its size in a 32bit number
        placeUOffset(vectorElementAmount)

        nested = false
        return currentOffset
    }

    private func placeUOffset(_ number: UOffset) {
        let byteSize = UOffset(UOffset.bitWidth / UInt8.bitWidth)
        spaceRemaining -= byteSize

        buffer.replaceSubrange(getBufferRange(rangeLength: byteSize), with: number.littleEndianData)
    }

    private func addNullTerimator() {
        spaceRemaining -= nullTerminatorByteSize
        buffer.insert(0, at: Int(currentOffset))
    }

    /**
     Gets a range of the buffer starting from the current offset with the length specified
     */
    private func getBufferRange(rangeLength: UOffset) -> Range<Data.Index> {
        return buffer.startIndex.advanced(by: Int(currentOffset))..<buffer.startIndex.advanced(by: Int(currentOffset + rangeLength + 1))
    }

    /**
      Should not be creating any other object, string or vector
      while an object is being constructed.
     */
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
}
