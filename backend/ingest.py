from dotenv import load_dotenv
load_dotenv()

import time
from langchain_community.document_loaders import PyPDFLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_google_genai import GoogleGenerativeAIEmbeddings
from langchain_community.vectorstores import FAISS

loader = PyPDFLoader("handbook.pdf")
docs = loader.load()
print(f"Loaded {len(docs)} pages")

splitter = RecursiveCharacterTextSplitter(chunk_size=800, chunk_overlap=150)
chunks = splitter.split_documents(docs)
print(f"Split into {len(chunks)} chunks")

embeddings = GoogleGenerativeAIEmbeddings(model="gemini-embedding-001")

batch_size = 20  # smaller batches to be safe
vectorstore = None

for i in range(0, len(chunks), batch_size):
    batch = chunks[i:i + batch_size]
    batch_num = i // batch_size + 1
    total_batches = (len(chunks) - 1) // batch_size + 1
    print(f"Embedding batch {batch_num}/{total_batches} ({len(batch)} chunks)...")

    success = False
    while not success:
        try:
            if vectorstore is None:
                vectorstore = FAISS.from_documents(batch, embeddings)
            else:
                batch_store = FAISS.from_documents(batch, embeddings)
                vectorstore.merge_from(batch_store)
            success = True
        except Exception as e:
            print(f"Rate limit hit, waiting 30 seconds before retry... ({e})")
            time.sleep(30)

    if i + batch_size < len(chunks):
        print("Waiting 15 seconds before next batch...")
        time.sleep(15)

vectorstore.save_local("faiss_index")
print("Saved vector store to faiss_index/")