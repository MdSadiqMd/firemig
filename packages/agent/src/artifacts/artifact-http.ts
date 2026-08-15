export interface ArtifactHttpResponse {
    status: number;
    headers: Headers;
    body: AsyncIterable<Uint8Array> | null;
}

export type ArtifactHttpClient = (url: string, init: RequestInit) => Promise<ArtifactHttpResponse>;

export const fetchArtifact: ArtifactHttpClient = async (url, init) => {
    const response = await fetch(url, init);
    return {
        status: response.status,
        headers: response.headers,
        body: response.body as unknown as AsyncIterable<Uint8Array> | null,
    };
};
