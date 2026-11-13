import time

from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from langchain_google_genai import GoogleGenerativeAIEmbeddings, ChatGoogleGenerativeAI
from langchain_community.vectorstores import FAISS
from langgraph.graph import StateGraph, END
from typing import TypedDict

embeddings = GoogleGenerativeAIEmbeddings(model="gemini-embedding-001")
vectorstore = FAISS.load_local("faiss_index", embeddings, allow_dangerous_deserialization=True)
retriever = vectorstore.as_retriever(search_kwargs={"k": 3})
llm = ChatGoogleGenerativeAI(model="gemini-3-flash-preview")

class ChatState(TypedDict):
    question: str
    context: str
    answer: str

def retrieve_node(state):
    t = time.time()
    docs = retriever.invoke(state["question"])
    print(f"retrieve took {time.time() - t:.1f}s")
    context = "\n\n".join(d.page_content for d in docs)
    return {"context": context}

def generate_node(state):
    t = time.time()
    prompt = f"""Answer the question using only the context below.
If the answer isn't in the context, say you don't know.

Context:
{state['context']}

Question: {state['question']}
"""
    result = llm.invoke(prompt)
    print(f"generate took {time.time() - t:.1f}s")

    # Handle both plain string and structured list content
    if isinstance(result.content, str):
        answer_text = result.content
    elif isinstance(result.content, list):
        answer_text = "".join(
            block.get("text", "") for block in result.content if isinstance(block, dict)
        )
    else:
        answer_text = str(result.content)

    return {"answer": answer_text}

graph = StateGraph(ChatState)
graph.add_node("retrieve", retrieve_node)
graph.add_node("generate", generate_node)
graph.set_entry_point("retrieve")
graph.add_edge("retrieve", "generate")
graph.add_edge("generate", END)
app_graph = graph.compile()

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

class Query(BaseModel):
    question: str

@app.post("/chat")
def chat(q: Query):
    try:
        result = app_graph.invoke({"question": q.question})
        return {"answer": result["answer"]}
    except Exception as e:
        import traceback
        traceback.print_exc()
        msg = str(e)
        if "RESOURCE_EXHAUSTED" in msg or "429" in msg:
            return {"answer": "Daily AI limit reached. Please try again later."}
        return {"answer": f"Server error: {e}"}

@app.get("/health")
def health_check():
    return {"status": "running"}

@app.get("/")
def root():
    return {"status": "running"}