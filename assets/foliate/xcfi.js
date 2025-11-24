/**
 * XCFI Module
 * 
 * Converter between EPUB CFI and CREngine XPointer (XPath)
 * Converts between foliate-js CFI format and KOReader CREngine XPointer format
 * 
 * Provides KOReader sync compatibility by converting between CFI and XPointer formats
 */

import { parse, collapse, toRange, toElement, fake, fromRange } from './epubcfi.js';

/**
 * Normalize XPointer by removing trailing /text().N segments and .N suffixes
 * Used to standardize XPointer paths for consistent comparison and storage
 */
export const normalizeProgressXPointer = (xpointer) => {
    let normalized = xpointer;
    // Remove trailing /text().N segments
    const tailingTextOffset = /\/text\(\).*$/;
    if (normalized.match(tailingTextOffset)) {
        normalized = normalized.replace(tailingTextOffset, '');
    }
    // Remove trailing .N suffixes after node steps
    const suffixNodeOffset = /\.\d+$/;
    if (normalized.match(suffixNodeOffset)) {
        normalized = normalized.replace(suffixNodeOffset, '');
    }
    return normalized;
};

/**
 * Find text node and offset within element based on cumulative character offset
 * Locates the specific text node and character position within an element
 */
export const findTextNodeAtOffset = (element, offset) => {
    const textNodes = [];
    const collectTextNodes = (el) => {
        for (const child of Array.from(el.childNodes)) {
            if (child.nodeType === Node.TEXT_NODE) {
                const text = child.textContent || '';
                if (text.length > 0) {
                    textNodes.push(child);
                }
            } else if (child.nodeType === Node.ELEMENT_NODE) {
                collectTextNodes(child);
            }
        }
    };
    collectTextNodes(element);

    let currentOffset = 0;
    for (const textNode of textNodes) {
        const nodeText = textNode.textContent || '';
        const nodeLength = nodeText.length;

        if (currentOffset + nodeLength >= offset) {
            return {
                node: textNode,
                offset: offset - currentOffset,
            };
        }

        currentOffset += nodeLength;
    }

    // If offset is beyond all text, return the last text node at its end
    if (textNodes.length > 0) {
        const lastNode = textNodes[textNodes.length - 1];
        return {
            node: lastNode,
            offset: (lastNode.textContent || '').length,
        };
    }

    return null;
};

/**
 * Adjust spine index in CFI
 * Converts 0-based spine index to CFI format (1-based with step calculation)
 */
export const adjustSpineIndex = (cfi, spineIndex) => {
    const spineStep = (spineIndex + 1) * 2; // Convert 0-based to CFI format
    const cfiMatch = cfi.match(/^epubcfi\((.+)\)$/);
    if (cfiMatch) {
        const innerCfi = cfiMatch[1];
        if (innerCfi.match(/^\/6\/\d+!/)) {
            const adjustedInner = innerCfi.replace(/^\/6\/\d+!/, `/6/${spineStep}!`);
            return `epubcfi(${adjustedInner})`;
        } else {
            const adjustedInner = `/6/${spineStep}!${innerCfi}`;
            return `epubcfi(${adjustedInner})`;
        }
    }
    return cfi;
};

/**
 * Check if an element is significant for XPointer path building
 * Filters out inline elements that don't affect document structure
 */
const isSignificantElement = (element) => {
    const tagName = element.tagName.toLowerCase();
    const inlineElements = new Set([
        'span', 'em', 'strong', 'i', 'b', 'u', 'small', 'mark', 'sup', 'sub'
    ]);
    return !inlineElements.has(tagName);
};

/**
 * Collect all text nodes in document order
 * Recursively gathers all non-empty text nodes from an element
 */
const collectTextNodes = (element, textNodes) => {
    for (const child of Array.from(element.childNodes)) {
        if (child.nodeType === Node.TEXT_NODE) {
            const text = child.textContent || '';
            if (text.length > 0) {
                textNodes.push(child);
            }
        } else if (child.nodeType === Node.ELEMENT_NODE) {
            collectTextNodes(child, textNodes);
        }
    }
};

/**
 * Build XPointer path from DOM element
 * Constructs an XPath-like path identifying the element's position in the document
 */
const buildXPointerPath = (targetElement, spineItemIndex) => {
    const pathParts = [];
    let current = targetElement;

    // Build path from target back to root
    while (current && current !== current.ownerDocument.documentElement) {
        const parent = current.parentElement;
        if (!parent) break;

        const tagName = current.tagName.toLowerCase();
        // Count preceding siblings with same tag name (0-based for CREngine)
        let siblingIndex = 0;
        let totalSameTagSiblings = 0;
        for (const sibling of Array.from(parent.children)) {
            if (sibling.tagName.toLowerCase() === tagName) {
                if (sibling === current) {
                    siblingIndex = totalSameTagSiblings;
                }
                totalSameTagSiblings++;
            }
        }

        // Format as tag[index] (0-based for CREngine)
        // Omit [0] if there's only one element with this tag name
        if (totalSameTagSiblings === 1) {
            pathParts.unshift(tagName);
        } else {
            pathParts.unshift(`${tagName}[${siblingIndex + 1}]`); // Convert to 1-based index for XPointer
        }
        current = parent;
    }

    let xpointer = `/body/DocFragment[${spineItemIndex + 1}]`;
    if (pathParts.length > 0 && pathParts[0].startsWith('body')) {
        pathParts.shift();
    }
    xpointer += '/body';

    if (pathParts.length > 0) {
        xpointer += '/' + pathParts.join('/');
    }

    return xpointer;
};

/**
 * Handle text offset within an element by finding character position
 * Locates the specific text node and character offset for a given CFI offset
 */
const handleTextOffset = (element, cfiOffset, spineItemIndex) => {
    const textNodes = [];
    collectTextNodes(element, textNodes);

    let totalChars = 0;
    let targetTextNode = null;
    let offsetInNode = 0;

    for (const textNode of textNodes) {
        const nodeText = textNode.textContent || '';
        const nodeLength = nodeText.length;

        if (totalChars + nodeLength >= cfiOffset) {
            targetTextNode = textNode;
            offsetInNode = cfiOffset - totalChars;
            break;
        }

        totalChars += nodeLength;
    }

    if (!targetTextNode) {
        // Offset beyond text content, use element end
        return buildXPointerPath(element, spineItemIndex);
    }

    // Find the containing element for this text node
    let textParent = targetTextNode.parentElement;
    while (textParent && !isSignificantElement(textParent)) {
        textParent = textParent.parentElement;
    }

    if (!textParent) {
        textParent = element;
    }

    const basePath = buildXPointerPath(textParent, spineItemIndex);
    return `${basePath}/text().${offsetInNode}`;
};

/**
 * Handle text offset for a specific text node within an element
 * Calculates cumulative offset across all text nodes to locate position
 */
const handleTextOffsetInElement = (element, textNode, offset, spineItemIndex) => {
    // Find all text nodes in the element to calculate cumulative offset
    const textNodes = [];
    collectTextNodes(element, textNodes);

    let cumulativeOffset = 0;
    for (const node of textNodes) {
        if (node === textNode) {
            cumulativeOffset += offset;
            break;
        }
        cumulativeOffset += (node.textContent || '').length;
    }

    return handleTextOffset(element, cumulativeOffset, spineItemIndex);
};

/**
 * Convert a range point (container + offset) to XPointer
 * Transforms DOM range position into XPointer format for KOReader compatibility
 */
const rangePointToXPointer = (container, offset, spineItemIndex) => {
    if (container.nodeType === Node.TEXT_NODE) {
        // For text nodes, find the containing element
        const element = container.parentElement || container.ownerDocument.documentElement;
        return handleTextOffsetInElement(element, container, offset, spineItemIndex);
    } else if (container.nodeType === Node.ELEMENT_NODE) {
        const element = container;
        if (offset === 0) {
            if (element.childNodes.length > 0) {
                const firstChild = element.childNodes[0];
                if (firstChild.nodeType === Node.ELEMENT_NODE) {
                    return buildXPointerPath(firstChild, spineItemIndex);
                }
            }
            return buildXPointerPath(element, spineItemIndex);
        } else {
            // Offset points to a child node
            const childNodes = Array.from(element.childNodes);
            const targetChild = childNodes[offset - 1] || childNodes[childNodes.length - 1];

            if (targetChild && targetChild.nodeType === Node.ELEMENT_NODE) {
                return buildXPointerPath(targetChild, spineItemIndex);
            } else if (targetChild && targetChild.nodeType === Node.TEXT_NODE) {
                return handleTextOffsetInElement(
                    element,
                    targetChild,
                    (targetChild.textContent || '').length,
                    spineItemIndex
                );
            } else {
                return buildXPointerPath(element, spineItemIndex);
            }
        }
    } else {
        // Fallback to document element
        return buildXPointerPath(container.ownerDocument.documentElement, spineItemIndex);
    }
};

/**
 * Extract spine index from XPath
 * XPath uses 1-based indices, returns 0-based index for internal use
 */
export const extractSpineIndexFromXPath = (xpointer) => {
    const match = xpointer.match(/DocFragment\[(\d+)\]/);
    if (match) {
        // Convert 1-based to 0-based
        return parseInt(match[1], 10) - 1;
    }
    throw new Error(`Cannot extract spine index from XPath: ${xpointer}`);
};

/**
 * Convert CFI to XPointer (XPath) for KOReader sync support
 * Transforms EPUB CFI format to CREngine XPointer format
 */
export const convertCFIToXPointer = async (view, cfi) => {
    try {
        if (!view || !view.book) {
            throw new Error('View or book not available');
        }

        const parts = parse(cfi);
        let spineIndex;

        if (parts.parent) {
            // Range CFI
            spineIndex = fake.toIndex(parts.parent.shift()); // Remove the spine step
            const doc = await view.book.sections[spineIndex].createDocument();
            const range = toRange(doc, parts);
            const startXPointer = rangePointToXPointer(range.startContainer, range.startOffset, spineIndex);
            const endXPointer = rangePointToXPointer(range.endContainer, range.endOffset, spineIndex);
            return {
                xpointer: startXPointer,
                pos0: startXPointer,
                pos1: endXPointer
            };
        } else {
            // Collapsed CFI
            const collapsed = collapse(parts);
            spineIndex = fake.toIndex(parts.shift());
            const doc = await view.book.sections[spineIndex].createDocument();
            const element = toElement(doc, parts[0]);
            if (!element) {
                throw new Error(`Element not found for CFI: ${cfi}`);
            }

            const lastPart = collapsed[collapsed.length - 1]?.[collapsed[collapsed.length - 1].length - 1];
            const textOffset = lastPart?.offset;

            const xpointer = textOffset !== undefined
                ? handleTextOffset(element, textOffset, spineIndex)
                : buildXPointerPath(element, spineIndex);

            return { xpointer };
        }
    } catch (error) {
        throw error;
    }
};

/**
 * Convert XPath (XPointer) to CFI for KOReader sync support
 * Transforms CREngine XPointer format back to EPUB CFI format
 */
export const convertXPathToCFI = async (view, xpointer, logToFlutter = null) => {
    try {
        // Ensure book is loaded
        if (!view.book) {
            throw new Error('Book not loaded yet');
        }

        // Normalize XPointer first
        // This removes trailing /text().N and .N suffixes for consistent parsing
        const normalizedXPointer = normalizeProgressXPointer(xpointer);
        if (logToFlutter) {
            logToFlutter(`Normalized XPointer: ${normalizedXPointer} (from: ${xpointer})`);
        }

        // Extract spine index (1-based to 0-based conversion for internal use)
        const spineIndex = extractSpineIndexFromXPath(normalizedXPointer);
        if (logToFlutter) {
            logToFlutter(`Extracted spine index: ${spineIndex} (0-based from DocFragment)`);
        }

        // Load document from sections for XPointer resolution
        const sections = view.book?.sections || [];
        if (spineIndex >= sections.length) {
            throw new Error(`Spine index ${spineIndex} out of bounds (sections: ${sections.length})`);
        }

        const section = sections[spineIndex];
        if (!section || !section.createDocument) {
            throw new Error(`Section ${spineIndex} does not have createDocument method`);
        }

        const doc = await section.createDocument();
        if (logToFlutter) {
            logToFlutter(`Loaded document for spine index ${spineIndex} from sections`);
        }

        // Parse XPointer to find element
        // Format after normalization: /body/DocFragment[N]/body/element[1]/element2[2]/...
        // Text offset is extracted from original xpointer (before normalization)
        const textOffsetMatch = xpointer.match(/\/text\(\)\.(\d+)$/);
        const textOffset = textOffsetMatch ? parseInt(textOffsetMatch[1], 10) : undefined;

        // Remove text offset from normalized path for element resolution
        const pathForElement = textOffset !== undefined
            ? normalizedXPointer.replace(/\/text\(\)\.\d+$/, '')
            : normalizedXPointer;

        // Match path format: /body/DocFragment[N]/body(.*)
        const pathMatch = pathForElement.match(/^\/body\/DocFragment\[\d+\]\/body(.*)$/);
        if (!pathMatch) {
            // If no /body after DocFragment, it's just the start of the section (body element)
            const current = doc.body;
            const range = doc.createRange();
            if (textOffset !== undefined) {
                // Find text node at offset
                const textNodeInfo = findTextNodeAtOffset(current, textOffset);
                if (textNodeInfo) {
                    range.setStart(textNodeInfo.node, textNodeInfo.offset);
                    range.setEnd(textNodeInfo.node, textNodeInfo.offset);
                } else {
                    range.setStart(current, 0);
                    range.setEnd(current, 0);
                }
            } else {
                range.setStart(current, 0);
                range.setEnd(current, 0);
            }

            const cfi = fromRange(range);
            return adjustSpineIndex(cfi, spineIndex);
        }

        const elementPath = pathMatch[1] || '';

        // Resolve element path by traversing XPath segments
        let current = doc.body;
        if (elementPath && elementPath.trim() !== '') {
            const segments = elementPath.split('/').filter(Boolean);
            for (const segment of segments) {
                // Match tag[index] or just tag (1-based indices in XPath)
                const withIndexMatch = segment.match(/^(\w+)\[(\d+)\]$/);
                const withoutIndexMatch = segment.match(/^(\w+)$/);

                let tagName, index;
                if (withIndexMatch) {
                    tagName = withIndexMatch[1];
                    index = Math.max(0, parseInt(withIndexMatch[2], 10) - 1); // Convert 1-based to 0-based
                } else if (withoutIndexMatch) {
                    tagName = withoutIndexMatch[1];
                    index = 0;
                } else {
                    throw new Error(`Invalid XPath segment: ${segment}`);
                }

                const children = Array.from(current.children).filter(
                    child => child.tagName.toLowerCase() === tagName.toLowerCase()
                );

                if (index >= children.length) {
                    throw new Error(`Element index ${index} out of bounds for tag ${tagName}`);
                }

                current = children[index];
            }
        }
        // If elementPath is empty, current is already doc.body (start of section)

        // Create range from element for CFI conversion
        const range = doc.createRange();
        if (textOffset !== undefined) {
            // Find text node at offset within the element
            const textNodeInfo = findTextNodeAtOffset(current, textOffset);
            if (textNodeInfo) {
                range.setStart(textNodeInfo.node, textNodeInfo.offset);
                range.setEnd(textNodeInfo.node, textNodeInfo.offset);
            } else {
                // Fallback to element positioning
                range.setStart(current, 0);
                range.setEnd(current, 0);
            }
        } else {
            range.setStart(current, 0);
            range.setEnd(current, 0);
        }

        // Convert range to CFI
        const cfi = fromRange(range);

        // Adjust spine index in CFI to match EPUB structure
        return adjustSpineIndex(cfi, spineIndex);
    } catch (e) {
        if (logToFlutter) {
            logToFlutter(`Error converting XPath to CFI: ${e.message}`);
        }
        throw e;
    }
};



