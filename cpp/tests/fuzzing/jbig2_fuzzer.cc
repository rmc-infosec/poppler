#include <cstdint>
#include <vector>

#include "Object.h"
#include "Stream.h"
#include "JBIG2Stream.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    Object globals;
    Object dict;
    
    // Create a MemStream from the fuzzer data
    MemStream *memStream = new MemStream((const char *)data, 0, size, Object::null());
    
    // Create the JBIG2Stream. 
    // It takes ownership of memStream? Let's check FilterStream.
    // FilterStream(Stream *strA) stores it in 'str' and FilterStream::~FilterStream deletes it.
    // JBIG2Stream inherits from FilterStream.
    
    JBIG2Stream *jbig2Stream = new JBIG2Stream(memStream, std::move(globals), &dict);
    
    jbig2Stream->reset();
    
    // Consume the stream
    while (jbig2Stream->getChar() != EOF) {
        // Just consume
    }
    
    delete jbig2Stream;
    
    return 0;
}
