#include <cstdint>
#include <vector>
#include <span>

#include "FoFiTrueType.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    std::span<unsigned char> data_span(const_cast<unsigned char *>(data), size);
    
    std::unique_ptr<FoFiTrueType> fftt = FoFiTrueType::make(data_span, 0);
    if (fftt) {
        fftt->getNumCmaps();
        fftt->getEmbeddingRights();
        fftt->isOpenTypeCFF();
        
        double mat[6];
        fftt->getFontMatrix(mat);
        
        int nCmaps = fftt->getNumCmaps();
        for (int i = 0; i < nCmaps; ++i) {
            fftt->getCmapPlatform(i);
            fftt->getCmapEncoding(i);
            fftt->mapCodeToGID(i, 0);
        }
    }
    
    return 0;
}
