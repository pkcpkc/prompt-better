# JSON Specifications & Schemas

> Part of the [prompt-better docs](../README.md).

`prompt-better` uses three distinct JSON models.

### A. Prompt Specification (`prompt.json`)

Defines the name, model configs, dynamic placeholders (context), and structured outputs.

- **Schema Location**: [prompt-schema.json](../prompt_better/prompt_json/prompt-schema.json)
- **JSON Schema**:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Prompt Definition",
  "type": "object",
  "properties": {
    "name": {
      "type": "string",
      "description": "Unique identifier for the prompt."
    },
    "instructions": {
      "type": "object",
      "properties": {
        "prompt": {
          "type": "string",
          "description": "The system instructions or template for the model."
        },
        "context": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "name": { "type": "string" },
              "type": {
                "type": "string",
                "enum": ["string", "integer", "number", "boolean", "array"]
              },
              "desc": { "type": "string" }
            },
            "required": ["name", "type", "desc"]
          }
        }
      },
      "required": ["prompt", "context"]
    },
    "config": {
      "type": "object",
      "properties": {
        "model_id": { "type": "string" },
        "temperature": { "type": "number" },
        "top_p": { "type": "number" },
        "top_k": { "type": "integer" },
        "max_tokens": { "type": "integer" },
        "stop_sequences": { "type": "array", "items": { "type": "string" } }
      }
    },
    "outputs": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "type": {
            "type": "string",
            "enum": ["string", "integer", "number", "boolean", "array"]
          },
          "items": { "type": "string" },
          "desc": { "type": "string" }
        },
        "required": ["name", "type", "desc"]
      }
    }
  },
  "required": ["name", "instructions", "outputs"]
}
```

- **Example Specification**: [prompt.json](../example/prompts/TopicClassifier/prompt.json)

```json
{
  "name": "TopicClassifierPrompt",
  "config": {
    "temperature": 0.0,
    "max_tokens": 100
  },
  "instructions": {
    "prompt": "Classify the topic of the following text.\n\nText: {{text}}",
    "context": [
      {
        "name": "text",
        "type": "string",
        "desc": "The raw input text to analyze."
      }
    ]
  },
  "outputs": [
    {
      "name": "topic",
      "type": "string",
      "desc": "Must be one of: Politics, Sports, Technology, Science, Entertainment."
    }
  ]
}
```

---

### B. Dataset Case Specification (`caseX.json`)

Defines the inputs mapped to prompt placeholders, and optional conversation history messages.

> [!TIP]
> For a deeper dive into dataset design and curation, we recommend reading **Chapter 8. Dataset Engineering** in the book **"AI Engineering - Building Application with Foundation Models"** by **Chip Huyen** (O'Reilly).

- **Schema Location**: [dataset-schema.json](../prompt_better/dataset_manager/dataset-schema.json)
- **JSON Schema**:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Dataset Case Definition",
  "type": "object",
  "properties": {
    "id": {
      "type": "string",
      "description": "Unique identifier for this test case."
    },
    "inputs": {
      "type": "object",
      "additionalProperties": { "type": "string" },
      "description": "Key-value mapping of input placeholders to values."
    },
    "history": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "role": { "type": "string", "enum": ["user", "assistant", "system"] },
          "content": { "type": "string" },
          "prompt_name": { "type": "string" },
          "inputs": {
            "type": "object",
            "additionalProperties": { "type": "string" }
          }
        },
        "required": ["role"]
      }
    }
  },
  "required": ["inputs"]
}
```

- **Example Payload** (`dataset/case1.json`): [dataset/case1.json](../example/prompts/TopicClassifier/dataset/case1.json)

```json
{
  "id": "case1",
  "inputs": {
    "text": "Mars rover successfully collects rock sample."
  }
}
```

---

### C. Golden Truth Reference Specification (`caseX.json` next to dataset cases)

Defines expected ground truth values and human-written grading rubrics.

- **Schema Location**: [golden-schema.json](../prompt_better/dataset_manager/golden-schema.json)
- **JSON Schema**:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Golden Truth Definition",
  "type": "object",
  "properties": {
    "id": {
      "type": "string",
      "description": "Unique identifier matching the test case."
    },
    "reference_output": {
      "type": "object",
      "description": "Expected structured output key-value mapping."
    },
    "rubric": {
      "type": "array",
      "items": { "type": "string" },
      "description": "Quality criteria for evaluation."
    }
  },
  "required": ["reference_output"]
}
```

- **Example Payload** (`golden-truth/case1.json`): [golden-truth/case1.json](../example/prompts/TopicClassifier/golden-truth/case1.json)

```json
{
  "reference_output": {
    "topic": "Science"
  },
  "rubric": ["The output topic must be exactly Science."]
}
```
