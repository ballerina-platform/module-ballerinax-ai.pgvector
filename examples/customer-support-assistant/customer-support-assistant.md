# Customer support assistant with pgvector vector store

This example demonstrates the use of Ballerina pgvector vector store to build a customer support assistant. The system stores embeddings of past customer queries and retrieves relevant solutions based on vector similarity and metadata filtering.

## Step 1: Import the modules

Import the required modules for AI operations, I/O operations, UUID generation, and pgvector vector store.

```ballerina
import ballerina/ai;
import ballerina/io;
import ballerina/uuid;
import ballerinax/ai.pgvector;
```

## Step 2: Configure the application

Set up configurable variables for PostgreSQL database connection parameters.

```ballerina
configurable string host = ?;
configurable string user = ?;
configurable string password = ?;
configurable string database = ?;
configurable string tableName = ?;
```

## Step 3: Create a vector store instance

Initialize the pgvector vector store with your PostgreSQL database connection parameters.

```ballerina
pgvector:VectorStore vectorStore = check new (
    host,
    user,
    password,
    database,
    tableName,
    configs = {
        vectorDimension: 3
    }
);
```

Now, the `pgvector:VectorStore` instance can be used for storing and querying customer support embeddings.

## Step 4: Define the data structure

Define a record type to represent customer support queries with their embeddings and solutions.

```ballerina
type CustomerQuery record {
    float[] embedding;
    string query;
    string solution;
};
```

## Step 5: Prepare sample data

Create sample customer support data with queries, solutions, and their corresponding embeddings.

```ballerina
CustomerQuery[] entries = [
    {
        query: "How to reset my password?",
        solution: "To reset your password, please go to the login page and click on the Forgot Password link.",
        embedding: [0.1011, 0.20012, 0.3024]
    },
    {
        query: "How to change my email address?",
        solution: "To change your email address, please go to the profile page and click on the Change Email link.",
        embedding: [0.5645, 0.574, 0.3384]
    },
    {
        query: "How to delete my account?",
        solution: "To delete your account, please go to the profile page and click on the Delete Account link.",
        embedding: [0.789, 0.890, 0.901]
    }
];
```

## Step 6: Add data to the vector store

Store the customer support data in the pgvector vector store with embeddings and metadata.

```ballerina
ai:Error? addResult = vectorStore.add(from CustomerQuery entry in entries
    select {
        id: uuid:createRandomUuid(),
        embedding: entry.embedding,
        chunk: {
            'type: "text",
            content: entry.query,
            metadata: {
                "solution": entry.solution
            }
        }
    }
);
if addResult is ai:Error {
    io:println("Error occurred while adding an entry to the vector store", addResult);
    return;
}
```

## Step 7: Query the vector store

Search for similar customer support queries using vector similarity and apply metadata filters to refine the results.

```ballerina
// This is the embedding of the search query. It should use the same model as the embedding of the customer support entries.
ai:Vector searchEmbedding = [0.1, 0.2, 0.3];

ai:VectorMatch[]|error query = vectorStore.query({
    embedding: searchEmbedding,
    filters: {
        filters: [
            {
                'key: "solution",
                operator: ai:EQUAL,
                value: "To reset your password, please go to the login page and click on the Forgot Password link."
            }
        ]
    }
});
io:println("Query Results: ", query);
```
