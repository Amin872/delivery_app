import * as fs from "fs";
import * as path from "path";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import type { RulesTestEnvironment } from "@firebase/rules-unit-testing";

// storage.rules (Phase 31 H1/M6/L5). Needs BOTH the Storage and Firestore
// emulators: the orderProofs/vendorImages/promotions rules read orders,
// vendors and users through firestore.get(). Run with
//   firebase emulators:exec --only firestore,storage --project demo-delivery-rules \
//     "npm --prefix functions run test:rules"
// The project id must be the emulators' own project so the Storage
// emulator's firestore.get() sees the documents seeded here.
//
// Wrapped in one top-level describe() for the same root-suite-hook-ordering
// reason districts.rules.test.ts/neighborhoods.rules.test.ts document.
describe("storage.rules", () => {
  let testEnv: RulesTestEnvironment;

  const PROJECT_ID = "demo-delivery-rules";
  const CUSTOMER = "customer-1";
  const DRIVER = "driver-1";
  const OTHER_DRIVER = "driver-2";
  const VENDOR_OWNER = "vendor-owner-1";
  const OTHER_OWNER = "vendor-owner-2";
  const ADMIN = "admin-1";
  const STRANGER = "stranger-1";
  const ORDER = "order-1";

  const JPEG = { contentType: "image/jpeg" };
  const BYTES = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);

  function storage(uid: string | null) {
    const ctx = uid === null ? testEnv.unauthenticatedContext() : testEnv.authenticatedContext(uid);
    return ctx.storage();
  }

  function proofRef(uid: string | null, fileName = "proof.jpg", orderId = ORDER) {
    return storage(uid).ref(`orderProofs/${orderId}/${fileName}`);
  }

  // Orders carry vendorOwnerId exactly as the createOrder callable writes it
  // (Phase 32); [extra] overrides fields for specific cases.
  async function seedOrder(status: string, extra: Record<string, unknown> = {}) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`orders/${ORDER}`).set({
        customerId: CUSTOMER,
        vendorId: "vendor-1",
        vendorOwnerId: VENDOR_OWNER,
        driverId: DRIVER,
        status,
        items: [],
        total: 10,
        deliveryAddress: "Mezzeh",
        createdAt: Date.now(),
        ...extra,
      });
    });
  }

  async function seedProof() {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.storage().ref(`orderProofs/${ORDER}/proof.jpg`).put(BYTES, JPEG);
    });
  }

  before(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: fs.readFileSync(path.resolve(process.cwd(), "../firestore.rules"), "utf8"),
        host: "127.0.0.1",
        port: 8080,
      },
      storage: {
        rules: fs.readFileSync(path.resolve(process.cwd(), "../storage.rules"), "utf8"),
        host: "127.0.0.1",
        port: 9199,
      },
    });
  });

  after(async () => {
    await testEnv.cleanup();
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
    await testEnv.clearStorage();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc(`users/${ADMIN}`).set({ role: "admin" });
      await db.doc(`users/${CUSTOMER}`).set({ role: "customer" });
      await db.doc(`users/${DRIVER}`).set({ role: "driver" });
      await db.doc(`users/${OTHER_DRIVER}`).set({ role: "driver" });
      await db.doc(`users/${STRANGER}`).set({ role: "customer" });
      await db.doc("vendors/vendor-1").set({ ownerId: VENDOR_OWNER, approvalStatus: "approved" });
      await db.doc("vendors/vendor-2").set({ ownerId: OTHER_OWNER, approvalStatus: "approved" });
    });
  });

  describe("orderProofs read (H1)", () => {
    beforeEach(async () => {
      await seedOrder("delivered");
      await seedProof();
    });

    for (const [label, uid] of [
      ["the order's customer", CUSTOMER],
      ["the assigned driver", DRIVER],
      ["the vendor's owner", VENDOR_OWNER],
      ["an admin", ADMIN],
    ]) {
      it(`lets ${label} read the proof`, async () => {
        await assertSucceeds(proofRef(uid).getMetadata());
      });
    }

    for (const [label, uid] of [
      ["an unrelated signed-in customer", STRANGER],
      ["another driver", OTHER_DRIVER],
      ["another vendor's owner", OTHER_OWNER],
    ]) {
      it(`denies ${label}`, async () => {
        await assertFails(proofRef(uid).getMetadata());
      });
    }

    it("denies an unauthenticated read", async () => {
      await assertFails(proofRef(null).getMetadata());
    });

    it("denies reading a proof path whose order doesn't exist", async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.storage().ref("orderProofs/no-such-order/proof.jpg").put(BYTES, JPEG);
      });
      await assertFails(proofRef(CUSTOMER, "proof.jpg", "no-such-order").getMetadata());
    });
  });

  // Phase 32: vendor ownership comes ONLY from the order's server-written
  // vendorOwnerId — no vendors/{vendorId} lookup — so every read path
  // needs at most two Firestore documents (order, plus users/{uid} for admins).
  describe("orderProofs read — vendorOwnerId (Phase 32)", () => {
    it("the order's vendorOwnerId decides, not vendors/{vendorId}.ownerId", async () => {
      // vendor-1's real owner is VENDOR_OWNER, but the order names OTHER_OWNER.
      await seedOrder("delivered", { vendorOwnerId: OTHER_OWNER });
      await seedProof();
      await assertSucceeds(proofRef(OTHER_OWNER).getMetadata());
      await assertFails(proofRef(VENDOR_OWNER).getMetadata());
    });

    it("an order without vendorOwnerId grants no vendor access; other participants and admin unaffected", async () => {
      await seedOrder("delivered", { vendorOwnerId: null });
      await seedProof();
      await assertFails(proofRef(VENDOR_OWNER).getMetadata());
      await assertSucceeds(proofRef(CUSTOMER).getMetadata());
      await assertSucceeds(proofRef(DRIVER).getMetadata());
      await assertSucceeds(proofRef(ADMIN).getMetadata());
    });

    it("another vendor's owner and unassigned drivers stay denied", async () => {
      await seedOrder("delivered");
      await seedProof();
      for (const uid of [OTHER_OWNER, OTHER_DRIVER, STRANGER]) {
        await assertFails(proofRef(uid).getMetadata());
      }
    });

    it("reads are limited to proof.jpg, even for participants and admins", async () => {
      await seedOrder("delivered");
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.storage().ref(`orderProofs/${ORDER}/other.jpg`).put(BYTES, JPEG);
      });
      for (const uid of [CUSTOMER, DRIVER, VENDOR_OWNER, ADMIN]) {
        await assertFails(proofRef(uid, "other.jpg").getMetadata());
      }
    });
  });

  describe("orderProofs write (M6)", () => {
    for (const status of ["pickedUp", "delivering"]) {
      it(`lets the assigned driver upload proof.jpg while ${status}`, async () => {
        await seedOrder(status);
        await assertSucceeds(proofRef(DRIVER).put(BYTES, JPEG));
      });
    }

    for (const status of ["pending", "readyForPickup", "driverAssigned", "delivered", "cancelled"]) {
      it(`denies the assigned driver uploading while ${status}`, async () => {
        await seedOrder(status);
        await assertFails(proofRef(DRIVER).put(BYTES, JPEG));
      });
    }

    it("denies any file name other than proof.jpg", async () => {
      await seedOrder("delivering");
      for (const name of ["proof2.jpg", "proof.png", "extra.jpg", "proof.jpg.exe"]) {
        await assertFails(proofRef(DRIVER, name).put(BYTES, JPEG));
      }
    });

    it("denies another driver, the customer, the vendor owner and an admin", async () => {
      await seedOrder("delivering");
      for (const uid of [OTHER_DRIVER, CUSTOMER, VENDOR_OWNER, ADMIN]) {
        await assertFails(proofRef(uid).put(BYTES, JPEG));
      }
    });

    it("denies an unauthenticated upload", async () => {
      await seedOrder("delivering");
      await assertFails(proofRef(null).put(BYTES, JPEG));
    });

    it("denies uploading for an order that doesn't exist", async () => {
      await assertFails(proofRef(DRIVER, "proof.jpg", "no-such-order").put(BYTES, JPEG));
    });

    it("denies deleting a proof, even for the assigned driver", async () => {
      await seedOrder("delivering");
      await seedProof();
      await assertFails(proofRef(DRIVER).delete());
    });

    it("denies non-image or disallowed image types for proofs", async () => {
      await seedOrder("delivering");
      for (const contentType of ["image/svg+xml", "text/html", "application/pdf"]) {
        await assertFails(proofRef(DRIVER).put(BYTES, { contentType }));
      }
    });
  });

  describe("image content types (L5)", () => {
    function vendorImage(uid: string, vendorId = "vendor-1", fileName = "storefront.jpg") {
      return storage(uid).ref(`vendorImages/${vendorId}/${fileName}`);
    }

    for (const contentType of ["image/jpeg", "image/png", "image/webp"]) {
      it(`allows ${contentType} for vendor images, order proofs and promotions`, async () => {
        await seedOrder("delivering");
        await assertSucceeds(vendorImage(VENDOR_OWNER).put(BYTES, { contentType }));
        await assertSucceeds(proofRef(DRIVER).put(BYTES, { contentType }));
        await assertSucceeds(storage(ADMIN).ref("promotions/p1/media.jpg").put(BYTES, { contentType }));
      });
    }

    it("denies SVG everywhere images are accepted", async () => {
      await seedOrder("delivering");
      const svg = { contentType: "image/svg+xml" };
      await assertFails(vendorImage(VENDOR_OWNER).put(BYTES, svg));
      await assertFails(proofRef(DRIVER).put(BYTES, svg));
      await assertFails(storage(ADMIN).ref("promotions/p1/media.svg").put(BYTES, svg));
    });

    it("denies other image/* types such as GIF", async () => {
      await assertFails(vendorImage(VENDOR_OWNER).put(BYTES, { contentType: "image/gif" }));
    });
  });

  describe("vendorImages (unchanged permissions)", () => {
    function vendorImage(uid: string | null, vendorId = "vendor-1", fileName = "storefront.jpg") {
      return storage(uid).ref(`vendorImages/${vendorId}/${fileName}`);
    }

    it("lets the owner upload their storefront, logo and menu images", async () => {
      for (const name of ["storefront.jpg", "logo.jpg", "menu_item-1.jpg"]) {
        await assertSucceeds(vendorImage(VENDOR_OWNER, "vendor-1", name).put(BYTES, JPEG));
      }
    });

    it("denies another vendor's owner, a customer and an unauthenticated user", async () => {
      await assertFails(vendorImage(OTHER_OWNER).put(BYTES, JPEG));
      await assertFails(vendorImage(CUSTOMER).put(BYTES, JPEG));
      await assertFails(vendorImage(null).put(BYTES, JPEG));
    });

    it("denies an upload of 5MB or more", async () => {
      const big = new Uint8Array(5 * 1024 * 1024);
      await assertFails(vendorImage(VENDOR_OWNER).put(big, JPEG));
    });

    it("keeps vendor images publicly readable", async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.storage().ref("vendorImages/vendor-1/storefront.jpg").put(BYTES, JPEG);
      });
      await assertSucceeds(vendorImage(null).getMetadata());
    });
  });

  describe("promotions (unchanged permissions)", () => {
    it("lets an admin upload a promotion video", async () => {
      await assertSucceeds(storage(ADMIN).ref("promotions/p1/media.mp4").put(BYTES, { contentType: "video/mp4" }));
    });

    it("denies a non-admin upload", async () => {
      await assertFails(storage(VENDOR_OWNER).ref("promotions/p1/media.jpg").put(BYTES, JPEG));
    });

    it("keeps promotion media publicly readable", async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.storage().ref("promotions/p1/media.jpg").put(BYTES, JPEG);
      });
      await assertSucceeds(storage(null).ref("promotions/p1/media.jpg").getMetadata());
    });
  });
});
