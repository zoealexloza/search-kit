/*
 * Jest mock for lightning/navigation (mapped in jest.config.js). The stub that ships with
 * sfdx-lwc-jest does not record calls, so tests could not check where a component navigates.
 */
import { createTestWireAdapter } from "@salesforce/wire-service-jest-util";

export const CurrentPageReference = createTestWireAdapter(jest.fn());

let navigateCalls = [];
let generateUrlCalls = [];

const Navigate = Symbol("Navigate");
const GenerateUrl = Symbol("GenerateUrl");

export const NavigationMixin = (Base) =>
  class extends Base {
    [Navigate](pageReference, replace) {
      navigateCalls.push({ pageReference, replace });
    }

    [GenerateUrl](pageReference) {
      generateUrlCalls.push(pageReference);
      const id = pageReference?.attributes?.recordId ?? "page";
      return Promise.resolve(`/support/detail/${id}`);
    }
  };
NavigationMixin.Navigate = Navigate;
NavigationMixin.GenerateUrl = GenerateUrl;

/** Every Navigate call since the last reset, oldest first. */
export const getNavigateCalls = () => navigateCalls;

/** Every GenerateUrl call since the last reset, oldest first. */
export const getGenerateUrlCalls = () => generateUrlCalls;

export const resetNavigationMock = () => {
  navigateCalls = [];
  generateUrlCalls = [];
};
