from locust import HttpUser, between, task


class ResearchUser(HttpUser):
    wait_time = between(0.2, 0.5)

    @task
    def compute(self):
        with self.client.get(
            "/compute",
            name="/compute",
            catch_response=True,
        ) as response:

            if response.status_code != 200:
                response.failure(
                    f"HTTP {response.status_code}"
                )
