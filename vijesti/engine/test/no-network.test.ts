import { describe, expect, it } from 'vitest';
import { createCdnClient } from '../cdn/loader.js';
import { NetworkDisabledError } from './setup.js';

describe('testovi nemaju mrežu', () => {
  it('globalni fetch baca', async () => {
    await expect(fetch('https://cdn.domovina.ai/channels/data/index.json')).rejects.toBeInstanceOf(
      NetworkDisabledError,
    );
  });

  it('loader s globalnim fetchom ne može do CDN-a', async () => {
    const cdn = createCdnClient({ fetch: (url, init) => fetch(url, init) });
    await expect(cdn.channelIndex()).rejects.toBeInstanceOf(NetworkDisabledError);
  });
});
