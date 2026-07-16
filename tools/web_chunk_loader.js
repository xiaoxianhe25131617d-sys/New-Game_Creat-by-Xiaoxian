(function () {
	'use strict';

	const nativeFetch = globalThis.fetch.bind(globalThis);
	const manifestUrl = new URL('index.chunks.json', document.baseURI);
	const manifestPromise = nativeFetch(manifestUrl, { credentials: 'same-origin' }).then((response) => {
		if (!response.ok) {
			throw new Error(`Failed loading Web chunk manifest: ${response.status}`);
		}
		return response.json();
	});

	function fileNameFromUrl(url) {
		const path = url.pathname;
		return decodeURIComponent(path.slice(path.lastIndexOf('/') + 1));
	}

	function streamParts(entry, request) {
		let partIndex = 0;
		let reader = null;

		return new ReadableStream({
			async pull(controller) {
				while (true) {
					if (reader == null) {
						if (partIndex >= entry.parts.length) {
							controller.close();
							return;
						}
						const partUrl = new URL(entry.parts[partIndex].name, manifestUrl);
						const response = await nativeFetch(partUrl, {
							cache: request.cache,
							credentials: request.credentials,
							signal: request.signal,
						});
						if (!response.ok || response.body == null) {
							throw new Error(`Failed loading Web chunk '${entry.parts[partIndex].name}'`);
						}
						reader = response.body.getReader();
					}

					const result = await reader.read();
					if (result.done) {
						reader = null;
						partIndex += 1;
						continue;
					}
					controller.enqueue(result.value);
					return;
				}
			},
			cancel(reason) {
				if (reader != null) {
					return reader.cancel(reason);
				}
				return undefined;
			},
		});
	}

	globalThis.fetch = async function (input, init) {
		const request = input instanceof Request ? input : new Request(input, init);
		const url = new URL(request.url, document.baseURI);
		const manifest = await manifestPromise;
		const entry = url.origin === manifestUrl.origin && request.method === 'GET'
			? manifest.files[fileNameFromUrl(url)]
			: null;

		if (entry == null) {
			return nativeFetch(input, init);
		}

		return new Response(streamParts(entry, request), {
			headers: {
				'Content-Length': String(entry.size),
				'Content-Type': entry.content_type,
			},
			status: 200,
		});
	};
}());
