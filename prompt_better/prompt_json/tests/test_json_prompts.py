from __future__ import annotations
import sys
import unittest
import tempfile
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from prompt_better.prompt_json import load_prompt_specs  # noqa: E402
from prompt_better.cli import _available_generation_languages, _resolve_generation_template  # noqa: E402
from prompt_better.prompt_json import generate_from_json  # noqa: E402



class JSONPromptTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp_dir_obj = tempfile.TemporaryDirectory()
        self.prompts_dir = Path(self.tmp_dir_obj.name)
        
        # Create ArticleInsightPrompt fixture
        article_insight_dir = self.prompts_dir / "ArticleInsight"
        article_insight_dir.mkdir(parents=True, exist_ok=True)
        article_insight_file = article_insight_dir / "prompt.json"
        article_insight_file.write_text(json.dumps({
            "name": "ArticleInsightPrompt",
            "instructions": {
                "prompt": "Summarize this article:\n\nArticle: {{input}}",
                "context": [
                    {
                        "name": "input",
                        "type": "string",
                        "desc": "The raw input text."
                    }
                ]
            },
            "outputs": [
                {
                    "name": "summary",
                    "type": "string",
                    "desc": "A concise summary of the article."
                },
                {
                    "name": "questions",
                    "type": "array",
                    "desc": "A list of three follow-up questions.",
                    "items": "string",
                    "min_count": 3,
                    "max_count": 3
                }
            ]
        }, indent=2), encoding="utf-8")
        
        # Create SearchSummaryPrompt fixture
        search_summary_dir = self.prompts_dir / "SearchSummary"
        search_summary_dir.mkdir(parents=True, exist_ok=True)
        search_summary_file = search_summary_dir / "prompt.json"
        search_summary_file.write_text(json.dumps({
            "name": "SearchSummaryPrompt",
            "instructions": {
                "prompt": "Synthesize search results:\n\nQuery: {{query}}\nContext: {{articleContext}}",
                "context": [
                    {
                        "name": "query",
                        "type": "string",
                        "desc": "The search query."
                    },
                    {
                        "name": "articleContext",
                        "type": "string",
                        "desc": "The search context."
                    }
                ]
            },
            "outputs": [
                {
                    "name": "summary",
                    "type": "string",
                    "desc": "A synthesis of the search results."
                }
            ]
        }, indent=2), encoding="utf-8")

        # Create ResearchResultPrompt fixture
        research_result_dir = self.prompts_dir / "ResearchResult"
        research_result_dir.mkdir(parents=True, exist_ok=True)
        research_result_file = research_result_dir / "prompt.json"
        research_result_file.write_text(json.dumps({
            "name": "ResearchResultPrompt",
            "instructions": {
                "prompt": "Extract findings from this text:\n\nText: {{input}}",
                "context": [
                    {
                        "name": "input",
                        "type": "string",
                        "desc": "The raw input text."
                    }
                ]
            },
            "outputs": [
                {
                    "name": "answer",
                    "type": "string",
                    "desc": "The extracted findings using references formatted like [article_id]."
                }
            ]
        }, indent=2), encoding="utf-8")

        self.specs = load_prompt_specs(self.prompts_dir)

    def tearDown(self) -> None:
        self.tmp_dir_obj.cleanup()

    def test_extracts_article_insight(self) -> None:
        self.assertIn("ArticleInsightPrompt", self.specs)
        spec = self.specs["ArticleInsightPrompt"]
        self.assertEqual(spec.placeholders, ["input"])
        self.assertIn("input", [field.name for field in spec.fields])
        self.assertIn("summary", [field.name for field in spec.fields])
        self.assertIn("questions", [field.name for field in spec.fields])

    def test_count_becomes_json_schema_bounds(self) -> None:
        self.assertIn("ArticleInsightPrompt", self.specs)
        schema = self.specs["ArticleInsightPrompt"].to_json_schema()
        questions = schema["schema"]["properties"]["questions"]
        self.assertEqual(questions["minItems"], 3)
        self.assertEqual(questions["maxItems"], 3)

    def test_search_summary_placeholders_include_query_and_context(self) -> None:
        self.assertIn("SearchSummaryPrompt", self.specs)
        spec = self.specs["SearchSummaryPrompt"]
        self.assertEqual(sorted(spec.placeholders), ["articleContext", "query"])

    def test_research_result_description_is_kept(self) -> None:
        self.assertIn("ResearchResultPrompt", self.specs)
        schema = self.specs["ResearchResultPrompt"].to_json_schema()
        description = schema["schema"]["properties"]["answer"]["description"]
        self.assertIn("[article_id]", description)

    def test_save_to_source(self) -> None:
        import tempfile
        import json
        with tempfile.TemporaryDirectory() as tmpdir:
            temp_file = Path(tmpdir) / "TestPrompt.json"
            spec = self.specs["ArticleInsightPrompt"]
            spec.source_path = temp_file
            
            # Save it
            spec.save_to_source()
            
            # Read back
            content = temp_file.read_text(encoding="utf-8")
            data = json.loads(content)
            self.assertEqual(data["name"], "ArticleInsightPrompt")
            self.assertEqual(data["instructions"]["prompt"], spec.instructions.prompt)

    def test_generate_from_json_uses_custom_template(self) -> None:
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            template = tmp / "custom.jinja2"
            target = tmp / "ArticleInsightPrompt.swift"
            template.write_text("generated {{ spec.name }}\n", encoding="utf-8")

            generate_from_json(
                self.prompts_dir / "ArticleInsight" / "prompt.json",
                target,
                template,
            )

            self.assertEqual(target.read_text(encoding="utf-8"), "generated ArticleInsightPrompt\n")

    def test_resolve_generation_template_for_swift_language(self) -> None:
        class Args:
            template = None
            language = "swift"

        template = _resolve_generation_template(Args())

        self.assertEqual(template.name, "swift.jinja2")
        self.assertTrue(template.exists())

    def test_available_generation_languages_come_from_templates(self) -> None:
        self.assertIn("swift", _available_generation_languages())

    def test_resolve_generation_template_for_custom_template(self) -> None:
        class Args:
            template = "custom/template.jinja2"
            language = None

        self.assertEqual(_resolve_generation_template(Args()), Path("custom/template.jinja2"))

    def test_resolve_generation_template_reports_missing_language(self) -> None:
        class Args:
            template = None
            language = "kotlin"

        with self.assertRaises(SystemExit) as context:
            _resolve_generation_template(Args())

        self.assertIn("kotlin", str(context.exception))
        self.assertIn("Available languages", str(context.exception))


if __name__ == "__main__":
    unittest.main()
