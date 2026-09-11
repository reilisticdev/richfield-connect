import json
import os

from dotenv import load_dotenv
from flask import Flask, jsonify, request
from flask_cors import CORS
from google import genai
from google.genai import types
from pydantic import BaseModel, Field

load_dotenv()

# gemini-2.5-flash is Google's confirmed low-latency choice for this service.
# Note for whoever reads this later: Google has slated 2.5 Flash for shutdown
# no earlier than 2026-10-16, replaced by 3.5 Flash - fine for the hackathon
# timeline, but if this service is still running after that date, swap this
# one constant.
MODEL_NAME = "gemini-2.5-flash"

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")

# The mobile app keeps the conversation client-side and replays it on every
# turn. Without these caps a long chat grows the prompt (and the Gemini bill)
# without limit, and one pasted essay can blow the request size.
MAX_HISTORY_TURNS = 20
MAX_TURN_CHARS = 4000

app = Flask(__name__)
CORS(app)

# CV PDFs are usually a few hundred KB; 5 MB leaves room for scanned ones.
# MAX_CONTENT_LENGTH makes Flask refuse a larger body before reading it (the
# 413 handler below keeps that response JSON, like every other error here).
MAX_CV_PDF_BYTES = 5 * 1024 * 1024
app.config["MAX_CONTENT_LENGTH"] = MAX_CV_PDF_BYTES + 64 * 1024

_client = genai.Client(api_key=GEMINI_API_KEY) if GEMINI_API_KEY else None


class ParsedCV(BaseModel):
    first_name: str | None = Field(default=None, description="Extracted first name, or null if not found")
    last_name: str | None = Field(default=None, description="Extracted last name, or null if not found")
    professional_headline: str = Field(
        description="A generated 1-sentence summary of their career/student status"
    )
    skills: list[str] = Field(description="Array of technical and soft skills")
    education_summary: str = Field(description="Extracted education details")


class SkillSuggestions(BaseModel):
    skills: list[str] = Field(
        description="3 to 6 specific, industry-recognised skills the user does not already list, most valuable first"
    )
    reason: str = Field(description="One short sentence on why these fit this user's programme and interests")


SYSTEM_PROMPT = (
    "You are the Richfield Connect Onboarding Assistant. You help students and alumni "
    "build elite professional profiles. Keep responses concise, encouraging, and highly "
    "specific to the user's current profile data. If their profile is missing skills, "
    "suggest specific ones based on their headline. Write plain conversational text; short "
    "bullet lists starting with '- ' are fine, but do not use Markdown headings or tables."
)

# Appended to SYSTEM_PROMPT when the app opens the assistant in guided mode
# (first-time setup). This is what makes onboarding step-by-step rather than
# a single generic answer: one missing section per reply, in priority order,
# skipping anything the profile JSON already shows as done.
ONBOARDING_PROMPT = (
    "You are running the guided onboarding flow. Work through the user's profile one "
    "section at a time, in this priority order: professional headline, skills, education, "
    "experience or projects, about/bio, external links (GitHub or LinkedIn), profile photo. "
    "Skip any section the profile JSON already shows as filled in. In each reply: briefly "
    "acknowledge what the user just said, then focus on exactly ONE missing section - say in "
    "one sentence why recruiters care about it, and give one ready-to-use suggestion (for "
    "example a drafted headline, or 3-5 specific skills that fit their programme) or ask one "
    "concrete question. Keep replies under 120 words. When every section is complete, "
    "congratulate them and suggest browsing opportunities. Never claim you have changed their "
    "profile - the user saves changes themselves in the app."
)


def _require_client() -> genai.Client:
    if _client is None:
        raise RuntimeError("GEMINI_API_KEY is not configured on the server")
    return _client


@app.get("/health")
def health():
    return jsonify(
        status="ok",
        gemini_configured=bool(GEMINI_API_KEY),
        supabase_configured=bool(
            os.environ.get("SUPABASE_URL") and os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
        ),
    )


CV_EXTRACTION_PROMPT = (
    "Extract structured profile information from this CV/resume. If a field "
    "genuinely cannot be determined, use null (for the name fields) or an empty "
    "array/string as appropriate - never invent information that isn't actually "
    "present in the CV."
)


@app.post("/api/parse-cv")
def parse_cv():
    """Takes a PDF upload (multipart/form-data, field "file") or JSON
    {"cv_text": "..."}. Gemini reads the PDF directly, so the app does no text
    extraction and scanned CVs work too. Nothing is stored."""
    upload = request.files.get("file")
    if upload is not None:
        pdf_bytes = upload.read()
        if not pdf_bytes:
            return jsonify(error="The uploaded file is empty"), 400
        if len(pdf_bytes) > MAX_CV_PDF_BYTES:
            return jsonify(error="CV PDFs must be 5 MB or smaller"), 413
        # Trust the bytes, not the filename or the client's content type.
        if not pdf_bytes.startswith(b"%PDF-"):
            return jsonify(error="Only PDF files are supported"), 400
        contents = [
            types.Part.from_bytes(data=pdf_bytes, mime_type="application/pdf"),
            CV_EXTRACTION_PROMPT,
        ]
    else:
        data = request.get_json(silent=True) or {}
        cv_text = data.get("cv_text")
        if not isinstance(cv_text, str) or not cv_text.strip():
            return jsonify(error="Send a PDF as 'file' or a non-empty 'cv_text' string"), 400
        contents = f"{CV_EXTRACTION_PROMPT}\n\nCV TEXT:\n{cv_text}"

    try:
        client = _require_client()
        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=contents,
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=ParsedCV,
            ),
        )
        if not response.text:
            return jsonify(error="The model returned an empty response"), 502
        parsed = ParsedCV.model_validate_json(response.text)
        return jsonify(parsed.model_dump()), 200
    except RuntimeError as e:
        return jsonify(error=str(e)), 500
    except Exception as e:
        app.logger.exception("parse_cv failed")
        return jsonify(error=f"Failed to parse CV: {e}"), 500


@app.post("/api/suggest-skills")
def suggest_skills():
    data = request.get_json(silent=True) or {}
    user_profile = data.get("user_profile")
    if not isinstance(user_profile, dict):
        return jsonify(error="user_profile is required and must be a JSON object"), 400

    existing = user_profile.get("skills") or []
    have = {s.strip().lower() for s in existing if isinstance(s, str)}

    try:
        client = _require_client()
        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=(
                "Suggest skills this Richfield student or alumnus should add to their profile "
                "next, based on their programme, headline, career interests and experience. "
                "Do not repeat skills they already list. Prefer concrete skill names recruiters "
                "search for (for example 'Docker', 'SQL', 'Figma', 'Stakeholder communication') "
                "over vague ones.\n\n"
                f"PROFILE (JSON):\n{json.dumps(user_profile)}"
            ),
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=SkillSuggestions,
            ),
        )
        if not response.text:
            return jsonify(error="The model returned an empty response"), 502
        parsed = SkillSuggestions.model_validate_json(response.text)

        # The prompt asks the model not to repeat existing skills, but that is
        # a request, not a guarantee - enforce it here so the app never offers
        # to "add" something the user already has.
        seen = set(have)
        skills = []
        for s in parsed.skills:
            name = s.strip()
            if name and name.lower() not in seen:
                seen.add(name.lower())
                skills.append(name)
        return jsonify(skills=skills[:6], reason=parsed.reason), 200
    except RuntimeError as e:
        return jsonify(error=str(e)), 500
    except Exception as e:
        app.logger.exception("suggest_skills failed")
        return jsonify(error=f"Failed to suggest skills: {e}"), 500


def _history_to_contents(history):
    """Validates the client-supplied transcript and maps it onto Gemini turns.

    Returns (contents, error_message). Leading assistant turns are dropped:
    the app may render a local greeting before the user has said anything,
    and Gemini expects a conversation to open with a user turn.
    """
    if not isinstance(history, list):
        return None, "history must be an array"

    contents = []
    for turn in history[-MAX_HISTORY_TURNS:]:
        if not isinstance(turn, dict):
            return None, "each history entry must be an object"
        role = turn.get("role")
        text = turn.get("text")
        if role not in ("user", "assistant") or not isinstance(text, str) or not text.strip():
            return None, "each history entry needs role 'user' or 'assistant' and non-empty text"
        if not contents and role == "assistant":
            continue
        contents.append(
            types.Content(
                role="user" if role == "user" else "model",
                parts=[types.Part(text=text[:MAX_TURN_CHARS])],
            )
        )
    return contents, None


@app.post("/api/chat")
def chat():
    data = request.get_json(silent=True) or {}
    message = data.get("message")
    user_profile = data.get("user_profile", {})
    history = data.get("history", [])
    mode = data.get("mode", "chat")

    if not isinstance(message, str) or not message.strip():
        return jsonify(error="message is required and must be a non-empty string"), 400
    if not isinstance(user_profile, dict):
        return jsonify(error="user_profile must be a JSON object"), 400
    if mode not in ("chat", "onboarding"):
        return jsonify(error="mode must be 'chat' or 'onboarding'"), 400

    contents, history_error = _history_to_contents(history)
    if history_error:
        return jsonify(error=history_error), 400
    contents.append(
        types.Content(role="user", parts=[types.Part(text=message[:MAX_TURN_CHARS])])
    )

    # The profile lives in the system instruction rather than a user turn so
    # it stays in force for the whole conversation instead of scrolling out
    # of the history window.
    system_instruction = SYSTEM_PROMPT
    if mode == "onboarding":
        system_instruction += "\n\n" + ONBOARDING_PROMPT
    system_instruction += (
        "\n\nThe user's current profile state (JSON):\n" + json.dumps(user_profile)
    )

    try:
        client = _require_client()
        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=contents,
            config=types.GenerateContentConfig(system_instruction=system_instruction),
        )
        if not response.text:
            return jsonify(error="The model returned an empty response"), 502
        return jsonify(reply=response.text), 200
    except RuntimeError as e:
        return jsonify(error=str(e)), 500
    except Exception as e:
        app.logger.exception("chat failed")
        return jsonify(error=f"Failed to generate reply: {e}"), 500


@app.errorhandler(404)
def not_found(_e):
    return jsonify(error="Not found"), 404


@app.errorhandler(405)
def method_not_allowed(_e):
    return jsonify(error="Method not allowed"), 405


@app.errorhandler(413)
def payload_too_large(_e):
    return jsonify(error="That upload is too large. CV PDFs must be 5 MB or smaller"), 413


if __name__ == "__main__":
    app.run(debug=True)
