## Overview

The Ballerina pgvector module provides an API for integrating with the `pgvector` extension for PostgreSQL. It implements the Ballerina AI `ai:VectorStore` interface which allows users to store, retrieve, and search high-dimensional vectors.

## Setup guide

You need a running PostgreSQL instance with the `pgvector` extension enabled. For that you can use the official pgvector Docker image.

```docker
docker run --name pgvector-db \
  -e POSTGRES_PASSWORD=mypassword \
  -e POSTGRES_DB=vector_db \
  -p 5432:5432 \
  -d pgvector/pgvector:pg17
```

To enable the pgvector extension, connect to the database and execute the following query.

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

## Quick Start

To use the pgvector vector store in your Ballerina project, modify the `.bal` file as follows.

### Step 1: Import the module

```ballerina
import ballerina/ai;
import ballerinax/ai.pgvector;
```

### Step 2: Initialize the Pgvector vector store

```ballerina
ai:VectorStore vectorStore = check new(
   options = {
      ssl: {
         mode: postgresql:DISABLE // use only if the SSL is disabled
      }
   },
   connectionConfigs = {
      host,
      user,
      password,
      database,
      tableName
   },
   vectorDimension = 3
);
```

### Step 3: Invoke the operations

```ballerina
ai:Error? result = vectorStore.add(
   [
      {
         id: uuid:createRandomUuid(),
         embedding: [1.0, 2.0, 3.0],
         chunk: {
               'type: "text", 
               content: "This is a chunk"
         }
      }
   ]
);

ai:VectorMatch[]|ai:Error matches = vectorStore.query({
   embedding: [1.0, 2.0, 3.0],
   filters: {
      // optional metadata filters
   }
});
```
