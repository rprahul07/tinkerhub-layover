// Gemini via the official Google Gen AI SDK (@google/genai), streamed.
import { GoogleGenAI } from '@google/genai';

export function createGemini({ apiKey, model, thinkingLevel, baseUrl }) {
  // baseUrl is only overridden in tests, to point the SDK at a local mock.
  const ai = new GoogleGenAI({ apiKey, ...(baseUrl ? { httpOptions: { baseUrl } } : {}) });

  return {
    name: 'gemini',
    model,
    // Yields text chunks as Gemini produces them. [modelOverride] lets calls
    // use a faster model than chat.
    async *stream({ system, history, signal, modelOverride }) {
      const config = {
        systemInstruction: system,
        maxOutputTokens: 2048,
        abortSignal: signal,
      };
      if (thinkingLevel) config.thinkingConfig = { thinkingLevel };

      const response = await ai.models.generateContentStream({
        model: modelOverride || model,
        contents: history.map((m) => ({ role: m.role === 'user' ? 'user' : 'model', parts: [{ text: m.text }] })),
        config,
      });
      for await (const chunk of response) {
        const text = chunk.text;
        if (text) yield text;
      }
    },

    // One structured answer that matches [schema] (JSON Schema), parsed.
    async json({ system, prompt, parts, schema, signal }) {
      const config = {
        systemInstruction: system,
        maxOutputTokens: 4096,
        responseMimeType: 'application/json',
        responseJsonSchema: schema,
        abortSignal: signal,
      };
      if (thinkingLevel) config.thinkingConfig = { thinkingLevel };
      const response = await ai.models.generateContent({ model, contents: [{ role: 'user', parts: parts ?? [{ text: prompt }] }], config });
      return JSON.parse(response.text ?? '');
    },
  };
}
