# AIToolImage

Generate images from text prompts using the OpenAI Images API (DALL-E / GPT-Image).

Unlike the other `AITool*` classes that are self-contained, `AIToolImage` requires an **OpenAI client instance** because it delegates to `$client.images.generate()`.

## Quick start

```4d
var $client:=cs.AIKit.OpenAI.new()
var $tool:=cs.AIToolImage.new($client)
$helper.registerTools($tool)
```

## Constructor

```4d
cs.AIToolImage.new($client : Object {; $config : Object})
```

| Parameter | Type | Description |
|---|---|---|
| `$client` | Object | **Required.** An `OpenAI` client instance (`cs.AIKit.OpenAI.new()`) |
| `$config` | Object | Optional configuration (see below) |

### Configuration options

| Key | Type | Default | Description |
|---|---|---|---|
| `defaultModel` | Text | `"dall-e-3"` | Model used when the LLM doesn't specify one |
| `defaultSize` | Text | `"1024x1024"` | Image dimensions when not specified |
| `defaultStyle` | Text | `""` (API default) | `"vivid"` or `"natural"` (DALL-E-3 only) |
| `maxPromptLength` | Integer | `4000` | Reject prompts longer than this |
| `allowedModels` | Collection | `["dall-e-2","dall-e-3","gpt-image-1"]` | Restrict which models can be requested |
| `allowedSizes` | Collection | `["256x256","512x512","1024x1024","1024x1792","1792x1024"]` | Restrict which sizes are accepted |
| `outputFolder` | 4D.Folder | `Null` | When set, generated images are automatically saved to this folder |

## Exposed tools

| Tool name | Description |
|---|---|
| `generate_image` | Generate an image from a text prompt. Returns a JSON object with the image URL, model, size, and optional `revised_prompt` and `saved_to` path. |

### generate_image parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `prompt` | string | Yes | Text description of the image to generate |
| `size` | string | No | Image dimensions (default: `1024x1024`) |
| `model` | string | No | Model (default: `dall-e-3`) |
| `style` | string | No | `"vivid"` or `"natural"` (DALL-E-3 only) |

### Response format

```json
{
  "success": true,
  "url": "https://oaidalleapiprodscus.blob.core.windows.net/...",
  "model": "dall-e-3",
  "size": "1024x1024",
  "revised_prompt": "A photorealistic ...",
  "saved_to": "/PACKAGE/images/image_2024-01-15T143022.png"
}
```

## Example — standalone

```4d
var $client:=cs.AIKit.OpenAI.new()
var $tool:=cs.AIToolImage.new($client; {\
  defaultModel: "dall-e-3"; \
  outputFolder: Folder("/PACKAGE/images")\
})

var $result:=$tool.generate_image({prompt: "A futuristic city at sunset"})
// → JSON with .url and .saved_to
```

## Example — with chat helper

```4d
var $client:=cs.AIKit.OpenAI.new()
var $tool:=cs.AIToolImage.new($client; {\
  allowedModels: New collection("dall-e-3"); \
  outputFolder: Folder(Temporary folder; fk platform path).folder("ai_images")\
})

var $helper:=$client.chat.create("You are a creative assistant that generates images on request."; {model: "gpt-4o"})
$helper.autoHandleToolCalls:=True
$helper.registerTools($tool)

var $result:=$helper.prompt("Generate an image of a cat wearing a top hat in a Victorian living room")
```

## Security considerations

| Risk | Mitigation |
|---|---|
| **Cost control** | Each image generation costs API credits. Use `dall-e-2` with `512x512` for development. DALL-E-3 at `1792x1024` is significantly more expensive. Restrict `allowedModels` and `allowedSizes` to control costs. |
| **Prompt injection** | The LLM composes the prompt — a malicious user could craft inputs that bypass content policy. The `maxPromptLength` cap limits the attack surface but does not prevent it. OpenAI's built-in content filter provides the main safety net. |
| **Disk usage** | When `outputFolder` is set, generated files accumulate. Implement periodic cleanup or set a quota outside this tool. |
| **Content policy** | Image generation is subject to OpenAI's content policy. Blocked requests return an error from the API. |
| **Network exposure** | The returned URL is a temporary Azure Blob Storage link. It expires after ~1 hour. If you share it, anyone with the link can view the image until expiry. Prefer saving to disk and serving through your own access-controlled endpoint. |

## Differences from other AITool classes

- **Requires a client**: `$client` (OpenAI instance) is the first constructor parameter.
- **External API call**: Generates the image server-side via OpenAI, unlike `AIToolWebFetch` or `AIToolCommand` which run locally.
- **Costs money**: Every successful call consumes API credits.
