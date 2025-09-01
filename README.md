# Ballerina Pgvector Vector Store Library

[![Build](https://github.com/ballerina-platform/module-ballerinax-ai.pgvector/workflows/Build/badge.svg)](https://github.com/ballerina-platform/module-ballerinax-ai.pgvector/actions?query=workflow%3ABuild)
[![GitHub Last Commit](https://img.shields.io/github/last-commit/ballerina-platform/module-ballerinax-ai.pgvector.svg)](https://github.com/ballerina-platform/module-ballerinax-ai.pgvector/commits/master)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

## Overview

Pgvector is a PostgreSQL extension that introduces a vector data type and similarity search capabilities for working with embeddings.

The Ballerina pgvector module provides an API for integrating with the `pgvector` extension for PostgreSQL. Its implementation allows it to be used as a Ballerina AI `ai:VectorStore`, enabling users to store, retrieve, and search high-dimensional vectors. 

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
   host,
   user,
   password,
   database,
   tableName,
   configs = {
      vectorDimension: 1536
   }
);
```

### Step 3: Invoke the operations

```ballerina
ai:Error? result = vectorStore.add(
   [
      {
         id: "1",
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

## Issues and projects

Issues and Projects tabs are disabled for this repository as this is part of the Ballerina Library. To report bugs, request new features, start new discussions, view project boards, etc., go to the [Ballerina Library parent repository](https://github.com/ballerina-platform/ballerina-standard-library).
This repository only contains the source code for the module.

## Build from the source

### Prerequisites

1. Download and install Java SE Development Kit (JDK) version 21 (from one of the following locations).

   - [Oracle](https://www.oracle.com/java/technologies/downloads/)
   - [OpenJDK](https://adoptium.net/)

     > **Note:** Set the JAVA_HOME environment variable to the path name of the directory into which you installed JDK.

2. Generate a GitHub access token with read package permissions, then set the following `env` variables:

   ```shell
   export packageUser=<Your GitHub Username>
   export packagePAT=<GitHub Personal Access Token>
   ```

### Build options

Execute the commands below to build from the source.

1. To build the package:

   ```bash
   ./gradlew clean build
   ```

2. To run the tests:

   ```bash
   ./gradlew clean test
   ```

3. To run a group of tests

   ```bash
   ./gradlew clean test -Pgroups=<test_group_names>
   ```

4. To build the without the tests:

   ```bash
   ./gradlew clean build -x test
   ```

5. To debug the package with a remote debugger:

   ```bash
   ./gradlew clean build -Pdebug=<port>
   ```

6. To debug with Ballerina language:

   ```bash
   ./gradlew clean build -PbalJavaDebug=<port>
   ```

7. Publish the generated artifacts to the local Ballerina central repository:

   ```bash
   ./gradlew clean build -PpublishToLocalCentral=true
   ```

8. Publish the generated artifacts to the Ballerina central repository:

   ```bash
   ./gradlew clean build -PpublishToCentral=true
   ```

## Contribute to Ballerina

As an open-source project, Ballerina welcomes contributions from the community.

For more information, go to the [contribution guidelines](https://github.com/ballerina-platform/ballerina-lang/blob/master/CONTRIBUTING.md).

## Code of conduct

All the contributors are encouraged to read the [Ballerina Code of Conduct](https://ballerina.io/code-of-conduct).
