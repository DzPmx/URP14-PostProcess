#ifndef OIT_LINKED_LIST_INCLUDED
#define OIT_LINKED_LIST_INCLUDED

#include "LinkedListStruct.hlsl"

StructuredBuffer<FragmentAndLinkBuffer_STRUCT> fragLinkedBuffer : register(t0);
ByteAddressBuffer startOffetBuffer : register(t1);


// Unity's HLSL seems not to support dynamic array size, so we can only set this before compilation
#define MAX_SORTED_PIXELS 16

//https://github.com/GameTechDev/AOIT-Update/blob/master/OIT_DX11/AOIT%20Technique/AOIT.hlsl
// UnpackRGBA takes a uint value and converts it to a float4
float4 UnpackRGBA(uint packedInput)
{
    float4 unpackedOutput;
    uint4 p = uint4((packedInput & 0xFFUL),
                    (packedInput >> 8UL) & 0xFFUL,
                    (packedInput >> 16UL) & 0xFFUL,
                    (packedInput >> 24UL));

    unpackedOutput = ((float4)p) / 255;
    return unpackedOutput;
}

float UnpackDepth(uint uDepthSampleIdx)
{
    return (float)(uDepthSampleIdx >> 8UL) / (pow(2, 24) - 1);
}

uint UnpackSampleIdx(uint uDepthSampleIdx)
{
    return uDepthSampleIdx & 0xFFUL;
}

float4 renderLinkedList(float4 col, float2 pos, uint uSampleIndex)
{
    // Fetch offset of first fragment for current pixel
    uint uStartOffsetAddress = 4 * (_ScreenParams.x * (pos.y - 0.5) + (pos.x - 0.5));
    uint uOffset = startOffetBuffer.Load(uStartOffsetAddress);

    FragmentAndLinkBuffer_STRUCT SortedPixels[MAX_SORTED_PIXELS];

    // Parse linked list for all pixels at this position
    // and store them into temp array for later sorting
    int nNumPixels = 0;
    while (uOffset != 0)
    {
        // Retrieve pixel at current offset
        FragmentAndLinkBuffer_STRUCT Element = fragLinkedBuffer[uOffset];
        uint uSampleIdx = UnpackSampleIdx(Element.uDepthSampleIdx);
        if (uSampleIdx == uSampleIndex)
        {
            SortedPixels[nNumPixels] = Element;
            nNumPixels += 1;
        }

        uOffset = (nNumPixels >= MAX_SORTED_PIXELS) ? 0 : fragLinkedBuffer[uOffset].next;
    }

    // Sort pixels in depth
    for (int i = 0; i < nNumPixels - 1; i++)
    {
        for (int j = i + 1; j > 0; j--)
        {
            float depth = UnpackDepth(SortedPixels[j].uDepthSampleIdx);
            float previousElementDepth = UnpackDepth(SortedPixels[j - 1].uDepthSampleIdx);
            if (previousElementDepth < depth)
            {
                FragmentAndLinkBuffer_STRUCT temp = SortedPixels[j - 1];
                SortedPixels[j - 1] = SortedPixels[j];
                SortedPixels[j] = temp;
            }
        }
    }

    // Rendering pixels
    for (int k = 0; k < nNumPixels; k++)
    {
        // Retrieve next unblended furthermost pixel
        float4 vPixColor = UnpackRGBA(SortedPixels[k].pixelColor);

        // Manual blending between current fragment and previous one
        col.rgb = lerp(col.rgb, vPixColor.rgb, vPixColor.a);
    }

    return col;
}
#endif // OIT_LINKED_LIST_INCLUDED
