export interface SseEvent {
    event: string;
    data: string;
    id?: string;
    retry?: number;
}

export async function* parseSse(stream: ReadableStream<Uint8Array>): AsyncGenerator<SseEvent> {
    const reader = stream.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    let firstChunk = true;
    try {
        while (true) {
            const { done, value } = await reader.read();
            buffer += decoder.decode(value, { stream: !done });
            if (firstChunk) {
                buffer = buffer.replace(/^\uFEFF/, "");
                firstChunk = false;
            }
            let boundary: RegExpExecArray | null;
            while ((boundary = /\r\n\r\n|\n\n|\r\r/.exec(buffer)) !== null) {
                const block = buffer
                    .slice(0, boundary.index)
                    .replace(/\r\n/g, "\n")
                    .replace(/\r/g, "\n");
                buffer = buffer.slice(boundary.index + boundary[0].length);
                const event = parseSseBlock(block);
                if (event !== undefined) yield event;
            }
            if (done) break;
        }
        if (buffer.trim() !== "") {
            const event = parseSseBlock(buffer.replace(/\r\n/g, "\n").replace(/\r/g, "\n"));
            if (event !== undefined) yield event;
        }
    } finally {
        reader.releaseLock();
    }
}

export function parseSseBlock(block: string): SseEvent | undefined {
    let event = "message";
    let id: string | undefined;
    let retry: number | undefined;
    const data: string[] = [];
    for (const line of block.split("\n")) {
        if (line === "" || line.startsWith(":")) continue;
        const colon = line.indexOf(":");
        const field = colon < 0 ? line : line.slice(0, colon);
        let value = colon < 0 ? "" : line.slice(colon + 1);
        if (value.startsWith(" ")) value = value.slice(1);
        if (field === "event") event = value;
        else if (field === "data") data.push(value);
        else if (field === "id" && !value.includes("\0")) id = value;
        else if (field === "retry" && /^\d+$/.test(value)) retry = Number(value);
    }
    if (data.length === 0) return undefined;
    return {
        event,
        data: data.join("\n"),
        ...(id === undefined ? {} : { id }),
        ...(retry === undefined ? {} : { retry }),
    };
}
